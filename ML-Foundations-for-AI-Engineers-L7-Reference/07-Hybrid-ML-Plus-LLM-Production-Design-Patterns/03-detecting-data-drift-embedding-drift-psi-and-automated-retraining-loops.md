# 07.3 · Detecting Data Drift, Embedding Drift & PSI, and Automated Retraining Loops

> **Folder 07 · Hybrid ML + LLM Production Design Patterns**
> **Measured on:** NumPy 2.5.4, SciPy 1.18.1 (KS tests), scikit-learn 1.9.1, the real CLINC150 router (LR head confidences on MiniLM embeddings), and a 16-week retraining simulation on real CLINC150 embeddings with a staged product launch and a seeded pipeline incident. Windows 11.
> **Design sources:** Rabanser et al. (*Failing Loudly*, 2019), Gama et al. (concept-drift survey, 2014), Lipton et al. (label shift, 2018), Gretton et al. (MMD, 2012), Page (CUSUM, 1954), Bifet & Gavaldà (ADWIN, 2007), Yurdakul (statistical properties of PSI, 2018), Shankar et al. (operationalizing ML, 2022), Ng (*Machine Learning in Production*). Full list in §8.

---

## 0. Orientation: Drift Detection Is Cheap; Fixing Drift Costs Labels; Retraining Without a Gate Is Dangerous

Every production model decays as the world changes: new products, new phrasings, new attack patterns, an upstream service that changes a field. The monitoring problem has three parts, and this file measures each one:

- **Drift metrics are noisy instruments.** PSI's false-alarm level depends on window size and bin count. Under *no* drift, its 99th percentile is **0.121** with 200-sample windows and 10 bins, and **0.879** with 50 bins. That's "major drift" by the usual rule of thumb, from noise alone. At 10,000 samples it's 0.0025. KS p-values go the other way: a trivial 0.02-sd shift gives **p = 1e-26** at a million samples. **Thresholds must be calibrated per window size, and alerts should fire on effect sizes, not p-values.**
- **Model-native signals are the cheapest drift detectors.** The PSI of the CLINC router's max-probability rises from **0.011** (no out-of-scope traffic) to **0.168** (20% OOS) to **0.617** (40% OOS). That's one number per window, with no embeddings stored.
- **The retraining loop needs a promotion gate.** In a 16-week simulation (30 new intents ramping to 35% of traffic, and a retraining job that silently used the wrong encoder version at weeks 8–9), **never retraining** decays to 0.556 accuracy. **Weekly retraining with a gate** averages 0.822. **Drift-triggered retraining without a gate** deployed the broken model at week 9 and **stayed broken for 7 weeks** (mean 0.480, worse than never retraining), because its drift reference reset to the broken model's own outputs. With the gate, the same drift trigger averaged 0.793 on just 2 retrains.

### The backend-engineer bridge

| You already know | Drift / retraining equivalent |
|---|---|
| Alert thresholds tuned per service from baseline noise | **Per-window, per-feature PSI thresholds** from the no-drift null |
| "p < 0.05" on a dashboard with millions of events | **KS p-values at scale**: always significant, so alert on effect size |
| Error rate and latency as health signals | **Confidence distribution, deferral share, OOS rate** as model-health signals |
| Synthetic probes vs real user complaints | **Drift signals** (fast, label-free) vs **labelled quality** (slow, ground truth) |
| A canary deploy with automatic rollback | **Champion/challenger promotion gate** on a golden set |
| A health check that only checks "the process is up" | **A drift monitor referenced to the deployed model's own outputs** |
| Scheduled vs event-driven jobs | **Scheduled vs drift-triggered retraining** |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 Kinds of change: covariate, prior, concept drift, and pipeline bugs | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 PSI: definition, its link to KL divergence, and binning | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Calibrating drift thresholds from the no-drift null | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 KS and other two-sample tests: effect size vs p-value | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Embedding drift: centroid shift, MMD, classifier two-sample tests, cluster shares | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Model-native signals: confidence, deferral share, OOS rate | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Label-delayed quality monitoring: sampling labels and their error bars | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Retraining policies: scheduled, triggered, continuous, and labels as the budget | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 The promotion gate: golden sets, serving-path evaluation, shadow and canary | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.10 Reference windows and the self-referential monitor trap | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.11 Sequential change detection: CUSUM, Page–Hinkley, ADWIN | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.12 Continual learning and catastrophic forgetting | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.13 Formal drift taxonomies and learning-theoretic guarantees under shift | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 Kinds of change: covariate, prior, concept drift, and pipeline bugs `[MUST-KNOW: Core AI Engineer Edge]`

Write the data distribution as p(x, y) = p(y | x)·p(x), or as p(x | y)·p(y). Each factor can change:

| Change | What moves | Example | Detectable without labels? | Typical fix |
|---|---|---|---|---|
| **Covariate shift** | p(x); p(y\|x) fixed | New phrasings, a new user segment, longer queries | Yes (input distribution) | Retrain on new inputs with labels; importance weighting |
| **Prior (label) shift** | p(y); p(x\|y) fixed | Attack rate rises, more refund requests after an outage | Partly (prediction distribution; BBSE, 06.1 §1.8) | Re-threshold or re-weight; no new features needed |
| **Concept drift** | p(y\|x) | A policy change: the same request now has a different correct answer | **No**, only through labels | New labels, retrain |
| **New classes** | The label space | New products or intents launch | Partly (OOS rate, low confidence) | Labels for the new classes, retrain |
| **Pipeline bugs** | Feature values for the same input | Unit change, null handling, embedding version (07.2) | Yes (sudden, often single-feature) | Fix the pipeline, not the model |

Two operational consequences:

- **Concept drift is invisible to every label-free monitor.** If the correct answer changes while inputs look the same, only labelled samples reveal it. That's why §1.7 exists.
- **A sudden shift in one feature is usually a bug, not the world.** Real drift is gradual and spread across features; pipeline bugs are step changes. Triage accordingly: check deploys and schema changes first.

### 1.2 PSI: definition, its link to KL divergence, and binning `[MUST-KNOW: Core AI Engineer Edge]`

Bin a reference sample (training data, or a trusted recent window) into B bins (usually quantile bins of the reference). Let p_b and q_b be the reference and current fractions in bin b:

```text
PSI = Σ_b (q_b − p_b) · ln(q_b / p_b)
    = KL(q ‖ p) + KL(p ‖ q)                 the symmetrized KL (Jeffreys divergence) of the binned distributions
```

Proof of the second line: KL(q‖p) + KL(p‖q) = Σ q ln(q/p) + Σ p ln(p/q) = Σ (q − p) ln(q/p). Every term is ≥ 0, because (q − p) and ln(q/p) always have the same sign. 01.3 §1.9 previewed this link.

**What PSI values mean physically.** For two normals with equal variance and means δ standard deviations apart, the continuous Jeffreys divergence is exactly δ². So:

| Shift (listing §3.1, section 1) | Continuous Jeffreys | Measured PSI (10 quantile bins) |
|---|---|---|
| None | 0 | 0.0016 (noise) |
| Mean +0.1 sd | 0.01 | 0.0064 |
| Mean +0.5 sd | 0.25 | 0.2306 |
| Std × 1.5 | (r² + 1/r² − 2)/2 = 0.347 | 0.1939 |

The common rule of thumb ("< 0.1 stable, 0.1–0.25 moderate, > 0.25 major") therefore means **"major" ≈ a half-standard-deviation mean shift**. Binning loses information in the tails, so a variance change scores much lower than its continuous divergence (0.19 vs 0.35). If tail behaviour matters (a guardrail score's extreme quantile), use more tail bins or a tail-specific statistic.

**Binning choices:** quantile bins of the reference (each bin has 1/B of the reference mass) are standard. Empty bins need a floor (the listing clips at 1e-6), and that floor dominates PSI when bins are sparse (§1.3).

### 1.3 Calibrating drift thresholds from the no-drift null `[MUST-KNOW: Core AI Engineer Edge]`

PSI between two samples of the *same* distribution isn't zero. Under the null, it's approximately a scaled chi-square:

```text
PSI_null ≈ χ²_{B−1} · (1/n + 1/m)          n = current window size, m = reference size
99th percentile of χ²_9 = 21.67
```

From listing §3.1, section 2 (500 trials per cell, reference m = 50,000):

| Window n | 99th pct PSI, 10 bins (χ² prediction) | 99th pct PSI, 50 bins |
|---|---|---|
| 200 | 0.1212 (0.109) | **0.8789** |
| 1,000 | 0.0221 (0.0221) | 0.0781 |
| 10,000 | 0.0025 (0.0026) | 0.0086 |

The chi-square formula predicts the 10-bin column almost exactly. With 50 bins and 200 samples (4 expected per bin), empty bins and the clipping constant dominate, and noise alone scores "major drift". The practical rules:

1. **Compute the null threshold for your window size and bin count**, by formula or by resampling the reference, and alert at a multiple of it (the retraining simulation uses 2 × the 99th percentile).
2. **Keep ≥ ~10 expected samples per bin** (B ≤ n/10).
3. **Tie the window to the decision.** Small windows react fast but need high thresholds. Large windows detect small shifts but react slowly. Hourly windows for a pipeline-bug alarm, daily or weekly for a retraining trigger.

### 1.4 KS and other two-sample tests: effect size vs p-value `[MUST-KNOW: Core AI Engineer Edge]`

The two-sample Kolmogorov–Smirnov statistic is D = sup_x |F_ref(x) − F_cur(x)|, the largest vertical gap between the two empirical CDFs. Its 5% critical value for equal sizes n is ≈ 1.36·√(2/n). Listing §3.1, section 3, fixes a tiny true shift (mean +0.02 sd, true D = 0.0080) and grows n:

| n | Measured D | 5% noise level 1.36·√(2/n) | p-value |
|---|---|---|---|
| 1,000 | 0.0610 | 0.0608 | 0.048 |
| 10,000 | 0.0123 | 0.0192 | 0.44 |
| 100,000 | 0.0070 | 0.0061 | 0.014 |
| 1,000,000 | 0.0078 | 0.0019 | **1e-26** |

At small n the statistic is mostly noise: 0.061 measured vs 0.008 true, and the "significant" p = 0.048 at n = 1,000 is luck. At large n, D converges to the true 0.008 while p collapses toward 0 for a shift nobody would act on. Production event volumes are in the millions, so **a p-value threshold on drift alarms pages on everything**. Alert on the **effect size** (D, PSI, a shift in a mean in sd units) above a level that matters, in windows large enough that the noise level is well below it.

Other tests you'll meet: the **χ² test** for categorical features, **Wasserstein distance** (in the feature's units, which helps interpretation), and **MMD** for multivariate data (§1.5).

### 1.5 Embedding drift: centroid shift, MMD, classifier two-sample tests, cluster shares `[MUST-KNOW: Core AI Engineer Edge]`

Embeddings are 384–4,096-dimensional, so per-dimension PSI is noisy and hard to interpret. 03.2 measured embedding-drift detectors directly. Their relative strengths:

- **Centroid shift** ‖μ_cur − μ_ref‖ (or the cosine between centroids): cheap, catches topic shifts, blind to changes in spread.
- **MMD** (maximum mean discrepancy, Gretton et al.): a kernel two-sample test on the full distribution, with a permutation null. The standard choice when you need a principled multivariate test.
- **Classifier two-sample test:** train a classifier to tell reference from current embeddings. AUC ≈ 0.5 means no drift, and its most confident examples *show you what changed*. Rabanser et al. (2019) found that univariate two-sample tests on a trained classifier's softmax outputs (black-box shift detection) were among the strongest detectors across shift types, which is the case for the model-native signals in §1.6.
- **Cluster-share drift:** assign each embedding to k-means clusters fitted on the reference (03.1), then compute PSI or χ² on the cluster shares. It's interpretable ("cluster 17: 'refund status' doubled") and it's the drift signal that maps directly to error analysis and labelling priorities.

03.2's measured warning applies here: a **fixed reference sample** re-used across many windows produced correlated false alarms (7/20) vs a freshly drawn reference split (1/20). Resample the reference, or account for its own noise in the threshold.

### 1.6 Model-native signals: confidence, deferral share, OOS rate `[MUST-KNOW: Core AI Engineer Edge]`

The model's own outputs are the cheapest and often the most relevant drift signals, because they only move when something the model cares about moves. Listing §3.1, section 4, mixes out-of-scope queries into 1,000-request windows of the CLINC router's traffic and computes PSI of the max-probability against a validation reference:

| OOS share in window | PSI of max-probability | Mean confidence |
|---|---|---|
| 0% | 0.0110 | 0.8710 |
| 5% | 0.0286 | 0.8431 |
| 10% | 0.0423 | 0.8278 |
| 20% | 0.1684 | 0.7669 |
| 40% | 0.6173 | 0.6433 |

At a 1,000-request window the no-drift 99th percentile is ~0.022 (§1.3). A 5-point rise in OOS traffic is barely detectable, 10 points is clear, and 20 points is unmistakable. The 0% row isn't zero, because validation vs test is itself a small shift.

Related signals in a cascade (07.1): the **deferral share** (a cost *and* a drift metric), the **OOS-gate rate**, and the **flag rate** of a guardrail (prior shift, 06.1 §1.8). All are one number per window, cheap to store, and directly tied to cost or quality.

**Their limitation:** they measure what the model *thinks*, not whether it's right. A model that becomes confidently wrong (concept drift, or a broken pipeline with a stable output distribution) can leave them flat. §1.10 shows the extreme case.

### 1.7 Label-delayed quality monitoring: sampling labels and their error bars `[MUST-KNOW: Core AI Engineer Edge]`

Only labels measure quality. Labels are slow (human review, delayed outcomes) and expensive, so production systems **sample**:

```text
weekly accuracy from n labelled items: ± 1.96·√(a(1 − a)/n)
n = 150, a ≈ 0.8:  ± 6.4 points          n = 1,000:  ± 2.5 points
```

At the simulation's labelling budget (150 a week), a weekly accuracy estimate is ±6 points. That's enough to catch a collapse, not a slow 2-point decay. Ways to stretch the budget:

- **Stratify by drift signal.** Over-sample low-confidence, deferred and new-cluster traffic, where errors concentrate, then re-weight to estimate overall accuracy.
- **Use validated proxies.** An LLM judge calibrated on human labels (06.3), or downstream outcomes (escalations, reformulations) with measured correlation to quality.
- **Pool over time** for slow trends. Use rolling 4-week windows for decay and weekly windows for incidents.

### 1.8 Retraining policies: scheduled, triggered, continuous, and labels as the budget `[MUST-KNOW: Core AI Engineer Edge]`

Listing §3.2 runs four policies on the same simulated world. A router launches knowing 120 of CLINC's 150 intents; 30 new intents launch at week 3 and ramp to 35% of traffic by week 12; 150 queries a week get labelled; the model is a nearest-centroid router with a cosine gate (cheap to refit). The retraining jobs at the end of weeks 8 and 9 embed their training data with a **different encoder version** (a pipeline incident, simulated by a random rotation).

| Policy | Gate | Mean accuracy (16 weeks) | Worst week | Retrains | Rejected |
|---|---|---|---|---|---|
| Never retrain | – | 0.6855 | 0.5559 | 0 | 0 |
| Every 4 weeks | no | 0.6372 | **0.1000** | 3 | 0 |
| Every 4 weeks | yes | 0.7633 | 0.5566 | 3 | 1 |
| PSI-triggered | no | **0.4800** | **0.1000** | 1 | 0 |
| PSI-triggered | yes | 0.7932 | 0.6197 | 2 | 1 |
| Weekly | no | 0.7405 | 0.1000 | 15 | 0 |
| Weekly | yes | **0.8215** | 0.7396 | 15 | 2 |

What the table teaches:

1. **Not retraining is a slow disaster:** 0.875 at launch, 0.556 by week 12, because 35% of traffic is intents the model doesn't know.
2. **Labels are the binding budget.** Even weekly retraining barely helps until enough labels of the new intents accumulate (a class needs ≥ 3 examples to get a centroid), so accuracy keeps falling until about week 7 under every policy. Drift is detectable without labels; it's *fixable* only with them.
3. **Drift triggers save compute but add lag.** PSI-triggered + gate retrained only twice and averaged 0.793, but its first trigger came at week 9 (new-intent share 24.5%), after accuracy had already fallen to 0.65. A rising curve crosses a fixed threshold late.
4. **Every ungated policy deployed the broken model**, and how long it stayed broken depended on the policy: 2 weeks (weekly), 4 weeks (every 4 weeks), 7 weeks and counting (PSI-triggered, §1.10).

**Choosing in practice:** scheduled retraining at a cadence your labelling can feed (weekly or monthly), *plus* a drift trigger for out-of-cycle retrains, *plus* a mandatory gate. Continuous (per-batch) training only when labels arrive continuously and the gate is automated.

### 1.9 The promotion gate: golden sets, serving-path evaluation, shadow and canary `[MUST-KNOW: Core AI Engineer Edge]`

The gate in the simulation is simple: **a candidate must not lose more than 0.5 points on a frozen, curated golden set (the CLINC validation split), scored through the serving path.** It rejected every broken candidate (accuracy ~10%) and passed every legitimate one. In production the gate has layers:

1. **Golden set.** Curated, versioned, covering every class including the new ones (written at launch, before traffic exists), plus known hard cases and regression examples from past incidents. Frozen between deliberate updates.
2. **Serving-path evaluation.** Score the candidate through the *same code path production uses*: the same feature pipeline and embedding version, the same preprocessing. The simulated incident is invisible to an evaluation that reuses the training pipeline's (broken) embeddings, because both would agree. It's obvious through the serving path.
3. **Champion/challenger comparison.** Paired on the same items (06.4 §1.3), with per-class floors (06.1) and a minimum-gain or maximum-loss rule.
4. **Shadow mode.** Run the candidate on live traffic without serving it, and compare its outputs, confidence distribution and deferral share with the champion's.
5. **Canary with automatic rollback.** A small traffic share with guardrail metrics (06.4 §1.9), rolled back on regression.

### 1.10 Reference windows and the self-referential monitor trap `[MUST-KNOW: Core AI Engineer Edge]`

The simulation's most important result is the ungated PSI-triggered policy. At week 9 the PSI crossed the threshold, a retrain ran, and the incident produced a broken model, which was deployed. The monitor then **reset its reference to the new model's outputs on recent traffic**, a natural design ("compare against post-deploy behaviour"). From then on it compared the broken model with itself: PSI stayed low, no trigger fired, and accuracy stayed at 0.10 for the remaining 7 weeks. Mean accuracy came to 0.480, worse than never retraining.

```text
reference = f_deployed(traffic at deploy time)
monitor   = PSI( f_deployed(traffic now), reference )    ← measures change in the MODEL'S VIEW of traffic
                                                            not whether the model is right
```

The defences:

- **A gate before every deploy** (§1.9), so a broken model never becomes the reference.
- **At least one monitor with a fixed, model-independent reference:** input drift against the training data, golden-set accuracy re-run daily through the serving path, or labelled samples (§1.7).
- **Sanity bounds on model outputs** independent of history: e.g. alert if > 50% of traffic is gated as OOS, or if the deferral share doubles. A broken model usually violates them immediately.

### 1.11 Sequential change detection: CUSUM, Page–Hinkley, ADWIN `[GOOD-TO-KNOW: Architectural Literacy]`

Window-vs-reference tests ask "is this window different?". Sequential detectors ask "has the mean changed, and when?", accumulating evidence across observations:

- **CUSUM** (Page, 1954): S_t = max(0, S_{t−1} + x_t − μ₀ − k), alarming when S_t > h. It's optimal (in a minimax sense) for detecting a mean shift of known size, and ideal for slowly rising signals like the deferral share or an error rate, which fixed-window thresholds catch late (§1.8, point 3).
- **Page–Hinkley:** a CUSUM variant common in stream-learning libraries.
- **ADWIN** (Bifet & Gavaldà, 2007): an adaptive window that shrinks when a change is detected, with false-alarm guarantees.

For the retraining trigger in §1.8, the weekly PSI sat just under the fixed 0.098 threshold in weeks 7–8 (0.079, 0.060) before crossing it at week 9. A CUSUM accumulates those excesses over the null mean instead of waiting for one window to cross, so it can fire earlier. Tune k and h on the no-drift null, as in §1.3. (⚠ Not run in the listing.)

### 1.12 Continual learning and catastrophic forgetting `[GOOD-TO-KNOW: Architectural Literacy]`

Fine-tuning a neural model only on recent data can **forget** older classes (catastrophic forgetting). Mitigations: retrain from scratch on all data (simple, and what the simulation does), **replay** a sample of older data in each fine-tuning batch, or regularize toward old weights (EWC, Kirkpatrick et al., 2017). For heads on frozen embeddings, full retraining is cheap enough that forgetting is a non-issue. For fine-tuned encoders and LoRA adapters (01.2), use replay plus a golden set with old-class floors.

### 1.13 Formal drift taxonomies and learning-theoretic guarantees under shift `[SKIP: Academic/Research Only]`

Domain-adaptation theory bounds target error by source error plus a divergence between domains (e.g. H-divergence). Formal taxonomies classify drift as sudden, gradual, incremental or recurring. They're useful vocabulary. The operational toolkit above (calibrated thresholds, model-native signals, labelled samples, gated retraining) is what keeps systems healthy.

---

## 2. Where It Beats an LLM in Production

**1. Monitoring is a classical-statistics job.** PSI, KS, MMD, CUSUM and labelled-sample estimates are microseconds-to-seconds of CPU per window, deterministic, and calibratable against a known null (§1.3). Asking an LLM to "look at today's traffic and tell me if something changed" gives an unquantified opinion with its own drift.

**2. Cheap models are cheap to retrain, and that changes the policy.** The centroid router in §3.2 refits in milliseconds, so weekly (or daily) retraining with a full promotion gate is practical, and it was the best policy (0.822 mean accuracy). A fine-tuned LLM can't be retrained weekly at that cost, and prompt changes are an unversioned, ungated substitute. The cascade (07.1) puts the frequently retrained, cheap stage in front, where drift lands first.

**3. Drift in LLM traffic is visible through cheap models.** The router's confidence PSI (§1.6), the deferral share, and cluster shares of query embeddings (§1.5) are drift monitors *for the LLM stage too*: when new topics appear, they show up first as deferrals and low-confidence clusters. The cheap stage is the LLM's early-warning system.

---

## 3. Production Code Blueprint

### 3.1 PSI and KS as drift alarms, and a model-native signal on real router scores

```python
"""psi_ks_drift_metrics.py - PSI and KS as drift alarms: what they measure, how they mislead, and on real router scores.

  1. PSI = sum (q - p) ln(q / p) over bins (a symmetrized KL, 01.3 s1.9): no drift vs mean shift vs variance shift.
  2. PSI's false alarms under NO drift depend on sample size and bin count.
  3. KS p-values: with enough data, a trivial shift is "significant" - alert on effect size, not p.
  4. Real signal: PSI of the CLINC router's confidence as out-of-scope traffic grows.
"""
import os

import numpy as np
from scipy import stats
from sklearn.linear_model import LogisticRegression

rng = np.random.default_rng(241)


def psi(ref, cur, bins=10):
    edges = np.unique(np.quantile(ref, np.linspace(0, 1, bins + 1)))
    cuts = np.r_[-np.inf, edges[1:-1], np.inf]
    p = np.histogram(ref, cuts)[0] / len(ref)
    q = np.histogram(cur, cuts)[0] / len(cur)
    p, q = np.clip(p, 1e-6, None), np.clip(q, 1e-6, None)
    return float(np.sum((q - p) * np.log(q / p)))


ref = rng.normal(0, 1, 50_000)
print("== 1. PSI for typical shifts (reference N(0,1), 10 quantile bins, 10,000 current samples) ==")
for name, cur in (("no drift", rng.normal(0, 1, 10_000)), ("mean +0.1 sd", rng.normal(0.1, 1, 10_000)),
                  ("mean +0.5 sd", rng.normal(0.5, 1, 10_000)), ("sd x1.5", rng.normal(0, 1.5, 10_000))):
    print(f"  {name:14s} PSI {psi(ref, cur):.4f}")
print("common rules of thumb: < 0.1 stable, 0.1-0.25 moderate, > 0.25 major shift")

print("\n== 2. PSI under NO drift: 99th percentile over 500 trials ==")
print(f"{'current n':>9} {'10 bins':>8} {'50 bins':>8}")
p99 = {}
for n in (200, 1000, 10_000):
    row = [np.percentile([psi(ref, rng.normal(0, 1, n), b) for _ in range(500)], 99) for b in (10, 50)]
    p99[n] = row
    print(f"{n:>9} {row[0]:>8.4f} {row[1]:>8.4f}")
print("small windows and many bins produce 'moderate drift' from noise alone -> calibrate thresholds per window size")
assert p99[200][1] > 0.1 and p99[10_000][0] < 0.01

print("\n== 3. KS test: a fixed, tiny shift (mean +0.02 sd) at growing sample sizes ==")
true_d = stats.norm.cdf(0.01) - stats.norm.cdf(-0.01)               # sup |F1 - F2| for N(0,1) vs N(0.02,1)
print(f"true KS distance of this shift: {true_d:.4f}")
for n in (1_000, 10_000, 100_000, 1_000_000):
    d, p = stats.ks_2samp(rng.normal(0, 1, n), rng.normal(0.02, 1, n))
    print(f"  n = {n:>9,}: KS statistic {d:.4f} (5% noise level 1.36*sqrt(2/n) = {1.36 * np.sqrt(2 / n):.4f}), p = {p:.2e}")
print("small windows: the statistic is mostly noise; huge windows: p -> 0 for a shift nobody would act on")
print("-> alert on the effect size (KS distance, PSI) above a level that matters, in windows where noise is below it")

print("\n== 4. real router scores: PSI of max-probability as OOS share grows (CLINC150, LR head) ==")
Z = np.load(os.path.join(os.environ["KB_DATA"], "clinc_minilm.npz"))
lr = LogisticRegression(C=10, max_iter=3000).fit(Z["X_train"], Z["y_train"])
conf_ref = lr.predict_proba(Z["X_val"]).max(1)
conf_in, conf_oos = lr.predict_proba(Z["X_test"]).max(1), lr.predict_proba(Z["X_oos_test"]).max(1)
print(f"{'OOS share in window':>19} {'PSI':>7} {'mean confidence':>16}")
vals = {}
for share in (0.0, 0.05, 0.10, 0.20, 0.40):
    k = int(1000 * share)
    w = np.r_[rng.choice(conf_in, 1000 - k, replace=False), rng.choice(conf_oos, k, replace=False)]
    vals[share] = psi(conf_ref, w)
    print(f"{share:>19.0%} {vals[share]:>7.4f} {w.mean():>16.4f}")
print("a cheap, model-native drift signal: no embeddings stored, one number per window")
assert vals[0.40] > vals[0.0] + 0.1
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. PSI for typical shifts (reference N(0,1), 10 quantile bins, 10,000 current samples) ==
  no drift       PSI 0.0016
  mean +0.1 sd   PSI 0.0064
  mean +0.5 sd   PSI 0.2306
  sd x1.5        PSI 0.1939
common rules of thumb: < 0.1 stable, 0.1-0.25 moderate, > 0.25 major shift

== 2. PSI under NO drift: 99th percentile over 500 trials ==
current n  10 bins  50 bins
      200   0.1212   0.8789
     1000   0.0221   0.0781
    10000   0.0025   0.0086
small windows and many bins produce 'moderate drift' from noise alone -> calibrate thresholds per window size

== 3. KS test: a fixed, tiny shift (mean +0.02 sd) at growing sample sizes ==
true KS distance of this shift: 0.0080
  n =     1,000: KS statistic 0.0610 (5% noise level 1.36*sqrt(2/n) = 0.0608), p = 4.84e-02
  n =    10,000: KS statistic 0.0123 (5% noise level 1.36*sqrt(2/n) = 0.0192), p = 4.36e-01
  n =   100,000: KS statistic 0.0070 (5% noise level 1.36*sqrt(2/n) = 0.0061), p = 1.42e-02
  n = 1,000,000: KS statistic 0.0078 (5% noise level 1.36*sqrt(2/n) = 0.0019), p = 9.95e-27
small windows: the statistic is mostly noise; huge windows: p -> 0 for a shift nobody would act on
-> alert on the effect size (KS distance, PSI) above a level that matters, in windows where noise is below it

== 4. real router scores: PSI of max-probability as OOS share grows (CLINC150, LR head) ==
OOS share in window     PSI  mean confidence
                 0%  0.0110           0.8710
                 5%  0.0286           0.8431
                10%  0.0423           0.8278
                20%  0.1684           0.7669
                40%  0.6173           0.6433
a cheap, model-native drift signal: no embeddings stored, one number per window

ALL ASSERTIONS PASSED
```

### 3.2 Scheduled vs drift-triggered retraining on real CLINC150 embeddings, with a promotion gate

```python
"""retraining_loop_simulation.py - scheduled vs drift-triggered retraining on real CLINC150 embeddings, with a promotion gate.

Scenario: a router launches knowing 120 of CLINC's 150 intents; the other 30 are products that launch at week 3 and
ramp to 35% of traffic by week 12 (10% of traffic is out-of-scope throughout). Each week:
  - the champion serves the week's traffic; accuracy is the mixture-weighted accuracy on the CLINC TEST split
  - a monitoring sample of 1,000 unlabelled test queries feeds a PSI drift check on the router's max-cosine score
  - 150 queries from that week's mix get labelled (drawn from the TRAIN split, so nothing leaks into evaluation)
Model: a nearest-centroid router with a cosine gate (same shape as 02.3's gate; cheap to refit).
INCIDENT: the retraining jobs at the end of weeks 8 and 9 embed their training data with a different encoder version
(simulated by a random rotation) - training/serving skew inside the retraining pipeline itself.
Promotion gate: a candidate must not lose more than 0.5 points on a frozen, curated golden set (the CLINC VAL split),
scored through the SERVING path.
"""
import os

import numpy as np

Z = np.load(os.path.join(os.environ["KB_DATA"], "clinc_minilm.npz"))
unit = lambda A: A / np.linalg.norm(A, axis=1, keepdims=True)
Xtr, ytr = unit(Z["X_train"]), Z["y_train"]
Xte, yte, Xo_te = unit(Z["X_test"]), Z["y_test"], unit(Z["X_oos_test"])
Xgold = np.vstack([unit(Z["X_val"]), unit(Z["X_oos_val"])])
ygold = np.r_[Z["y_val"], np.full(len(Z["X_oos_val"]), 150)]
OOS, WEEKS, BUDGET, BROKEN = 150, 16, 150, {8, 9}
world = np.random.default_rng(251)
new = np.sort(world.choice(150, 30, replace=False))
is_new = np.isin(np.arange(150), new)
share = lambda w: 0.35 * float(np.clip((w - 2) / 10, 0, 1))
Q = np.linalg.qr(world.normal(size=(384, 384)))[0]                 # the "other encoder version"

seed_idx, pool_old = [], []
for c in np.flatnonzero(~is_new):                                   # launch data: 50 per launched intent
    i = world.permutation(np.flatnonzero(ytr == c))
    seed_idx += list(i[:50])
    pool_old += list(i[50:])
pool_old, pool_new = list(world.permutation(pool_old)), list(world.permutation(np.flatnonzero(is_new[ytr])))
te_old, te_new = np.flatnonzero(~is_new[yte]), np.flatnonzero(is_new[yte])


def sample(s, r, n=1000):
    kind = r.choice(3, n, p=[0.9 - s, s, 0.1])
    return np.vstack([Xte[r.choice(te_old, (kind == 0).sum())], Xte[r.choice(te_new, (kind == 1).sum())],
                      Xo_te[r.choice(len(Xo_te), (kind == 2).sum())]])


mon = {w: sample(share(w), world) for w in range(WEEKS + 1)}       # the same traffic world for every policy
labels = {}
for w in range(1, WEEKS + 1):
    k = world.multinomial(BUDGET, [0.9 - share(w), share(w), 0.1])  # OOS labels are not used by the centroids
    labels[w] = [pool_old.pop() for _ in range(k[0])] + [pool_new.pop() for _ in range(k[1])]


def fit(idx, broken=False):
    X, y = Xtr[idx], ytr[idx]
    X = X @ Q if broken else X
    classes = np.flatnonzero(np.bincount(y, minlength=150) >= 3)    # a class needs >= 3 labelled examples
    return classes, unit(np.stack([X[y == c].mean(0) for c in classes]))


def predict(model, X):
    classes, C = model
    s = X @ C.T
    return np.where(s.max(1) >= TAU, classes[s.argmax(1)], OOS), s.max(1)


launch = fit(np.array(seed_idx))
known = ~np.r_[is_new, False][ygold]                               # launched intents + OOS
sims = Xgold[known] @ launch[1].T
grid = np.arange(0.20, 0.80, 0.01)
TAU = grid[int(np.argmax([np.mean(np.where(sims.max(1) >= t, launch[0][sims.argmax(1)], OOS) == ygold[known])
                          for t in grid]))]


def psi(ref, cur, bins=10):
    edges = np.quantile(ref, np.linspace(0, 1, bins + 1))[1:-1]
    p = np.histogram(ref, np.r_[-np.inf, edges, np.inf])[0] / len(ref)
    q = np.histogram(cur, np.r_[-np.inf, edges, np.inf])[0] / len(cur)
    p, q = np.clip(p, 1e-6, None), np.clip(q, 1e-6, None)
    return float(np.sum((q - p) * np.log(q / p)))


cal = np.random.default_rng(5)
null = [psi(predict(launch, sample(0, cal))[1], predict(launch, sample(0, cal))[1]) for _ in range(200)]
THRESH = 2 * float(np.percentile(null, 99))
print(f"{is_new.sum()} intents launch at week 3; cosine gate tau = {TAU:.2f} (tuned on the launch golden set)")
print(f"PSI alarm threshold = 2 x the no-drift 99th percentile ({np.percentile(null, 99):.4f}) = {THRESH:.4f}")


def evals(model):
    p_in, _ = predict(model, Xte)
    p_o, _ = predict(model, Xo_te)
    return np.mean(p_in[te_old] == yte[te_old]), np.mean(p_in[te_new] == yte[te_new]), np.mean(p_o == OOS)


def golden(model):
    return np.mean(predict(model, Xgold)[0] == ygold)


def run(policy, gate):
    champ = launch
    stats, gold, ref = evals(champ), golden(champ), predict(champ, mon[0])[1]
    data, accs, drifts, runs, rejected = list(seed_idx), [], [], 0, 0
    for w in range(1, WEEKS + 1):
        s = share(w)
        accs.append((0.9 - s) * stats[0] + s * stats[1] + 0.1 * stats[2])
        drifts.append(psi(ref, predict(champ, mon[w])[1]))
        data += labels[w]
        due = {"never": False, "every 4 weeks": w % 4 == 0, "PSI-triggered": drifts[-1] > THRESH, "weekly": True}[policy]
        if due and w < WEEKS:
            runs += 1
            cand = fit(np.array(data), broken=w in BROKEN)
            g = golden(cand)
            if gate and g < gold - 0.005:
                rejected += 1
                continue
            champ, stats, gold, ref = cand, evals(cand), g, predict(cand, mon[w])[1]
    return np.array(accs), np.array(drifts), runs, rejected


res = {(p, g): run(p, g) for p in ("never", "every 4 weeks", "PSI-triggered", "weekly") for g in (False, True)
       if not (p == "never" and g)}
cols = [("never", False), ("every 4 weeks", False), ("every 4 weeks", True), ("PSI-triggered", False),
        ("PSI-triggered", True), ("weekly", True)]
print("\n== weekly accuracy (mixture-weighted, CLINC test split) ==")
short = {"never": "never", "every 4 weeks": "4-weekly", "PSI-triggered": "PSI", "weekly": "weekly"}
print(f"{'week':>4} {'new share':>9} {'PSI never':>9} " + " ".join(f"{(short[p] + ('+gate' if g else '')):>13}" for p, g in cols))
for w in range(WEEKS):
    print(f"{w + 1:>4} {share(w + 1):>9.1%} {res[('never', False)][1][w]:>9.4f} "
          + " ".join(f"{res[c][0][w]:>13.4f}" for c in cols))

print(f"\n{'policy':16s} {'gate':>5} {'mean acc':>9} {'worst week':>10} {'retrains':>8} {'rejected':>8}")
for (p, g), (a, d, n, rj) in res.items():
    print(f"{p:16s} {('yes' if g else 'no'):>5} {a.mean():>9.4f} {a.min():>10.4f} {n:>8} {rj:>8}")
print("labels are the real budget: drift is detectable without labels, but only labelled data lets a retrain fix it")
never, psi_g, four = res[("never", False)][0], res[("PSI-triggered", True)][0], res[("every 4 weeks", False)][0]
assert psi_g.mean() > never.mean() + 0.03
assert four.min() < 0.5 and res[("every 4 weeks", True)][0].min() > 0.5
assert res[("weekly", True)][3] >= 2
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
30 intents launch at week 3; cosine gate tau = 0.33 (tuned on the launch golden set)
PSI alarm threshold = 2 x the no-drift 99th percentile (0.0491) = 0.0982

== weekly accuracy (mixture-weighted, CLINC test split) ==
week new share PSI never         never      4-weekly 4-weekly+gate           PSI      PSI+gate   weekly+gate
   1      0.0%    0.0115        0.8749        0.8749        0.8749        0.8749        0.8749        0.8749
   2      0.0%    0.0088        0.8749        0.8749        0.8749        0.8749        0.8749        0.8769
   3      3.5%    0.0073        0.8430        0.8430        0.8430        0.8430        0.8430        0.8424
   4      7.0%    0.0222        0.8111        0.8111        0.8111        0.8111        0.8111        0.8118
   5     10.5%    0.0263        0.7792        0.7804        0.7804        0.7792        0.7792        0.7804
   6     14.0%    0.0210        0.7473        0.7484        0.7484        0.7473        0.7473        0.7567
   7     17.5%    0.0785        0.7154        0.7165        0.7165        0.7154        0.7154        0.7467
   8     21.0%    0.0596        0.6835        0.6845        0.6845        0.6835        0.6835        0.7728
   9     24.5%    0.1001        0.6516        0.1000        0.6525        0.6516        0.6516        0.7562
  10     28.0%    0.1330        0.6197        0.1000        0.6206        0.1000        0.6197        0.7396
  11     31.5%    0.2091        0.5878        0.1000        0.5886        0.1000        0.8503        0.8503
  12     35.0%    0.2219        0.5559        0.1000        0.5566        0.1000        0.8483        0.8610
  13     35.0%    0.2410        0.5559        0.8653        0.8653        0.1000        0.8483        0.8653
  14     35.0%    0.2022        0.5559        0.8653        0.8653        0.1000        0.8483        0.8668
  15     35.0%    0.2124        0.5559        0.8653        0.8653        0.1000        0.8483        0.8706
  16     35.0%    0.2170        0.5559        0.8653        0.8653        0.1000        0.8483        0.8713

policy            gate  mean acc worst week retrains rejected
never               no    0.6855     0.5559        0        0
every 4 weeks       no    0.6372     0.1000        3        0
every 4 weeks      yes    0.7633     0.5566        3        1
PSI-triggered       no    0.4800     0.1000        1        0
PSI-triggered      yes    0.7932     0.6197        2        1
weekly              no    0.7405     0.1000       15        0
weekly             yes    0.8215     0.7396       15        2
labels are the real budget: drift is detectable without labels, but only labelled data lets a retrain fix it

ALL ASSERTIONS PASSED
```

**Reading the weekly table.** Follow three columns. *never* decays smoothly with the new-intent share. *4-weekly* (ungated) collapses to 0.10 for weeks 9–12 after deploying the week-8 broken candidate, then recovers at week 13. *PSI* (ungated) collapses at week 10 and never recovers: the self-referential trap (§1.10). The gated columns never drop below the champion they protect, and *weekly+gate* tracks the launch curve most closely, because it absorbs new labels fastest.

### 3.3 The retraining pipeline's contract

```text
trigger (schedule | drift alarm | manual)
  └─▶ snapshot data: training labels as-of now (point-in-time, 07.2), golden set version pinned
      └─▶ train candidate (versioned code, config, data snapshot, embedding version)
          └─▶ GATE 1: golden set through the SERVING path   (no class below its floor; ≤ 0.5-point loss)
              └─▶ GATE 2: paired comparison vs champion on recent labelled traffic (06.4 §1.3)
                  └─▶ GATE 3: shadow on live traffic: deferral share, confidence PSI, OOS rate within bounds
                      └─▶ canary 5% with auto-rollback on guardrails
                          └─▶ promote; reset drift references ONLY after promotion
monitors that never reset: input drift vs training data, daily golden-set run, labelled-sample accuracy
```

Each gate is cheap next to the cost of a week at 10% accuracy.

---

## 4. The Andrew Ng Lens: Production ML Is a Loop, Not a Launch

### 4.1 Concept drift and data drift in Ng's MLOps framing

Ng's *Machine Learning in Production* course distinguishes **data drift** (the input distribution changes) from **concept drift** (the input-to-output mapping changes), and frames deployment as the start of a monitoring and maintenance loop, not the end of a project. The simulation shows both halves of that loop: drift metrics tell you *that* the world changed, and labelled data plus retraining is what *responds*. Plan the labelling pipeline when you plan the model, because it's the budget that limits recovery (§1.8, point 2).

### 4.2 Error analysis on drift

When a drift alarm fires, the next step is the error-analysis spreadsheet (06.3), applied to the drifted slice: cluster the new traffic (§1.5), sample from the clusters that grew, label, tag, count. In the simulation, the drifted slice is "30 new intents". In production it's whatever the clusters say, and that determines whether the fix is new labels (new intents), a re-threshold (prior shift), or a pipeline fix (bug).

### 4.3 The golden set as a living dev set

Ng's dev-set discipline (fixed, representative, used to compare ideas) becomes the golden set in production. It must be **frozen between deliberate updates** (or every comparison moves the ruler), **updated when the product changes** (the 30 new intents were in the golden set from launch, which is how the gate could judge candidates fairly), and **scored through the serving path** (or it can't catch pipeline bugs).

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Drift alarms every day, ignored by on-call | PSI "moderate/major" on small windows | Thresholds not calibrated to window size or bins (null 99th pct 0.12–0.88 at n = 200) | Thresholds from the no-drift null per window | Null calibration job; ≥ 10 expected samples per bin |
| F2 | KS alarms on everything at scale | p ≈ 0 on trivial shifts | Alerting on p-values | Alert on effect size (D, PSI, sd shift) | Effect-size thresholds in the alert config |
| F3 | Model degraded with flat drift dashboards | Labelled accuracy down, inputs stable | Concept drift (or a stable-output broken model) | Labelled samples; golden-set runs | At least one monitor needs labels |
| F4 | Broken model stays deployed for weeks | Drift metrics flat after a deploy | Self-referential reference reset to the broken model | Gate before promotion; fixed-reference monitors | References reset only after gated promotion |
| F5 | Retrain makes things worse | Candidate worse on golden set | Pipeline incident (encoder version, data snapshot) | Reject at the gate; fix the pipeline | Serving-path golden-set gate, mandatory |
| F6 | Retraining doesn't fix the drop | New-class accuracy stays near 0 | Not enough labels for the new classes | Targeted labelling of new clusters | Labelling capacity planned per retrain cycle |
| F7 | Drift trigger fires too late | Threshold crossed after a long decline | Fixed-window threshold on a rising signal | CUSUM / sequential detection; scheduled retrains too | Combine schedule + trigger |
| F8 | Old classes regress after a fine-tune | Per-class floors violated | Catastrophic forgetting | Replay old data; retrain from scratch | Golden set with old-class floors |
| F9 | Embedding drift alarms after every re-index | Centroid shift at deploys only | A new embedding model or version, not traffic | Version-aware references; re-baseline after migrations | Embedding version in drift metadata (07.2 §1.7) |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "How do you know when to retrain the router?"</b></summary>

**Initial Prompt.** An intent router has been live for six months.

**L5 Answer.** "Monitor PSI and retrain when it goes above 0.25."

**Why L5 Fails in Production.** A fixed PSI threshold ignores window size (noise alone can exceed 0.25 on small windows), reacts late to gradual drift, is blind to concept drift, and says nothing about whether a retrain will help (labels?) or is safe (gate?).

**L7 Principal Defense.** "Three signals and a policy. Signals: (1) label-free drift, meaning confidence PSI, deferral share and embedding-cluster shares, with thresholds calibrated on the no-drift null for the window size. (2) A daily golden-set run through the serving path. (3) Labelled-sample accuracy, ±6 points weekly at 150 labels, so pooled over 4 weeks for trends. Policy: scheduled retraining at the cadence labelling can feed (weekly worked best in our simulation: 0.822 mean), plus drift-triggered out-of-cycle retrains, all through a mandatory promotion gate. In the simulation, the ungated drift-triggered policy averaged 0.480, worse than never retraining."

**Bar-Raiser Follow-ups.**
- *"Why was ungated drift-triggering so bad?"* It deployed a broken candidate, then reset its reference to that model's outputs, so the monitor compared the broken model with itself for 7 weeks.
- *"What's the cheapest thing to add first?"* The gate. It turns every other policy's worst case from 10% accuracy into "keep the champion".

</details>

<details><summary><b>Q2 · "Our PSI alerts fire constantly. Should we raise the threshold to 0.5?"</b></summary>

**Initial Prompt.** Hourly windows of ~200 requests, 50-bin PSI per feature.

**L5 Answer.** "Yes, 0.25 is too sensitive for our data."

**Why L5 Fails in Production.** The problem isn't the data. It's the window and bin count. With 200 samples and 50 bins, PSI's no-drift 99th percentile is 0.88, so even 0.5 fires on noise.

**L7 Principal Defense.** "Calibrate instead of guessing. Under no drift, PSI ≈ χ²_{B−1}·(1/n + 1/m). With 10 bins at n = 1,000 the 99th percentile is 0.022, matching our simulation exactly, while 50 bins at n = 200 gives 0.88, because the bins are nearly empty. Fixes: fewer bins (≥ 10 expected samples each), larger windows for drift questions (daily), hourly windows only for big pipeline-bug signals, and thresholds set at a multiple of the measured null per feature. Then alert on PSI *and* a minimum effect size, so the alerts mean something."

**Bar-Raiser Follow-ups.**
- *"What PSI means 'major' physically?"* About a half-standard-deviation mean shift: Jeffreys divergence δ² = 0.25.
- *"Per-feature or one global alarm?"* Per feature for diagnosis, plus model-native signals for paging. Page on what affects the model.

</details>

<details><summary><b>Q3 · "KS says p < 1e-20 on 5 of our features. Is the model at risk?"</b></summary>

**Initial Prompt.** Daily KS tests on millions of events.

**L5 Answer.** "Yes, that's extremely significant drift."

**Why L5 Fails in Production.** At millions of samples, any difference is significant. In our run, a 0.02-sd shift gave p = 1e-26 at n = 10⁶.

**L7 Principal Defense.** "The p-value answers 'is there any difference', and at this scale that's always yes. Look at the KS statistic D, the largest CDF gap. For our tiny shift it converged to the true 0.008, far below anything that would change predictions. I'd set effect-size thresholds per feature, informed by how much a shift of that size moves the model's output (or importance-weighted), and keep p-values only for small windows where noise matters. Then check the model-native signals: if confidence and deferral share are stable, the input drift probably doesn't matter to this model."

**Bar-Raiser Follow-ups.**
- *"When does the p-value help?"* In small windows, to separate a real shift from noise. There, the 5% critical value 1.36·√(2/n) is the useful number.

</details>

<details><summary><b>Q4 · "How do you detect drift in embeddings?"</b></summary>

**Initial Prompt.** A RAG system's query embeddings (768-d).

**L5 Answer.** "Compute PSI on each dimension."

**Why L5 Fails in Production.** 768 noisy per-dimension tests produce constant false alarms (multiple comparisons) and no interpretation. Embedding dimensions aren't meaningful features.

**L7 Principal Defense.** "Use multivariate or structural tests. (1) **Cluster-share drift:** k-means clusters fitted on reference queries, then PSI or χ² on cluster shares per day. It's interpretable ('billing-dispute cluster doubled') and maps straight to labelling priorities. (2) **MMD** with a permutation null when I need a principled test. (3) A **classifier two-sample test**: AUC tells me *how much*, and its confident examples show *what*. (4) **Model-native** signals: the router's confidence PSI rose from 0.011 to 0.168 as OOS traffic went from 0% to 20%. And re-sample the reference each time: 03.2 measured 7/20 false alarms with a fixed reference sample vs 1/20 with fresh splits."

**Bar-Raiser Follow-ups.**
- *"After an embedding model upgrade?"* Everything 'drifts' at once. Re-baseline the reference after the migration, with the version in the drift metadata.

</details>

<details><summary><b>Q5 · "Design the automated retraining pipeline for our intent router."</b></summary>

**Initial Prompt.** The team wants retraining without human involvement.

**L5 Answer.** "A nightly job that retrains on the latest labelled data and deploys."

**Why L5 Fails in Production.** Without a gate, a broken training run deploys automatically. In our simulation, ungated weekly retraining deployed a broken model twice (weeks 9–10 at 10% accuracy).

**L7 Principal Defense.** "Trigger → snapshot → train → gates → shadow → canary → promote. Point-in-time training data and a pinned golden-set version. Gate 1: the golden set scored *through the serving path*, so pipeline incidents like the wrong encoder version are caught. In the simulation every broken candidate scored ~10% and was rejected. Gate 2: a paired comparison against the champion on recent labelled traffic, with per-class floors. Gate 3: shadow traffic with bounds on deferral share and confidence PSI. Then a 5% canary with automatic rollback. Drift references reset only after promotion. Weekly cadence with the gate gave the best result (0.822 mean accuracy), and humans review rejections, not every run."

**Bar-Raiser Follow-ups.**
- *"What if the gate rejects every week?"* That's a pipeline incident or a stale golden set. Page a human, keep the champion.
- *"Where do the new intents' golden examples come from?"* They're written at product launch, before traffic exists, so the gate can judge new-class performance from day one.

</details>

<details><summary><b>Q6 · "Drift monitoring looks fine but customer complaints are rising. What's going on?"</b></summary>

**Initial Prompt.** All PSI dashboards are green.

**L5 Answer.** "Complaints are noisy; the metrics say the model is fine."

**Why L5 Fails in Production.** Label-free drift metrics can't see concept drift (the right answer changed for the same inputs), and monitors referenced to the deployed model can't see that the model itself is wrong.

**L7 Principal Defense.** "Two blind spots. (1) **Concept drift**: a policy or product change altered the correct answer for unchanged inputs. Only labels reveal it, so sample complaint-linked conversations, label them, and compare with the model's answers. (2) **Self-referential monitoring**: if the dashboards compare the current model with its own post-deploy outputs, a model that's been wrong since deploy looks perfectly stable. That's exactly how our ungated PSI policy stayed broken for 7 weeks. I'd check when the references were last reset relative to the last deploy, and run the golden set through the serving path today."

**Bar-Raiser Follow-ups.**
- *"Permanent fix?"* At least one quality monitor with a fixed reference (golden set or labelled sample), and complaint rate as a tracked downstream metric.

</details>

<details><summary><b>Q7 · "Should we retrain on a schedule or only when drift is detected?"</b></summary>

**Initial Prompt.** Retraining costs a few hours of GPU and an on-call review.

**L5 Answer.** "Only on drift; scheduled retraining wastes compute."

**Why L5 Fails in Production.** Drift triggers react late to gradual change (our trigger first fired at week 9, at 24.5% new-intent traffic), miss concept drift, and without a gate are actively dangerous.

**L7 Principal Defense.** "Both, plus a gate. In the simulation: weekly + gate averaged 0.822, PSI-triggered + gate 0.793 with only 2 retrains, every-4-weeks + gate 0.763. The trigger is compute-efficient but late. The schedule absorbs new labels steadily. I'd schedule at the cadence our labelling can feed, which is the real bottleneck, add a drift trigger (ideally CUSUM on the model-native signals, which reacts faster to gradual rises than a fixed threshold) for out-of-cycle retrains, and automate the gate so review is only needed on rejections. If retraining is expensive, a cheap trigger can decide *whether* this week's scheduled retrain runs."

**Bar-Raiser Follow-ups.**
- *"What if labels are monthly?"* Then retraining more often than monthly can't help. Spend the effort on targeted labelling of drifted clusters.

</details>

<details><summary><b>Q8 · "How many labels do we need each week to monitor accuracy?"</b></summary>

**Initial Prompt.** The labelling budget is being negotiated.

**L5 Answer.** "A hundred a week is enough to track accuracy."

**Why L5 Fails in Production.** At 100 labels, a weekly accuracy estimate is ±8 points. That catches a collapse but not a 2–3 point decay, the usual failure.

**L7 Principal Defense.** "Size it from the change you need to see: n ≈ 1.96²·a(1−a)/h² per window. At a ≈ 0.8, ±2.5 points needs ~1,000 labels. ±6.4 points needs 150, the simulation's budget. Options: (1) pool over 4 weeks for decay detection, weekly for incidents. (2) Stratify toward low-confidence, deferred and new-cluster traffic, where errors are, then re-weight. (3) Add a calibrated LLM judge as a proxy (06.3) with PPI for valid intervals. And remember the same labels feed retraining, so the budget serves both monitoring and recovery."

**Bar-Raiser Follow-ups.**
- *"Which matters more, monitoring or training labels?"* Training labels for new classes are what limited recovery in the simulation, so prioritize labelling the drifted clusters.

</details>

<details><summary><b>Q9 · "A drift alarm fired on one feature after this morning's deploy. Retrain?"</b></summary>

**Initial Prompt.** PSI on `session_duration` jumped from 0.01 to 12 overnight.

**L5 Answer.** "Yes, the data has drifted; retrain on recent data."

**Why L5 Fails in Production.** A step change in one feature right after a deploy is almost always a pipeline bug. Retraining on the broken feature would bake the bug into the model.

**L7 Principal Defense.** "Triage as an incident, not as drift. Real drift is gradual and spread across features; a 12.0 PSI step on one feature at deploy time is a unit or schema change. In 07.2, a ms-vs-s bug produced exactly PSI 12.4. Check the deploy diff for that feature's code path, run a replay diff (logged raw inputs through the offline feature code), fix the pipeline or roll back, and verify that PSI returns to baseline. Retrain only for real drift, and never on data produced by a known-broken pipeline: quarantine that window from the training set."

**Bar-Raiser Follow-ups.**
- *"Could the model adapt to the new units after retraining?"* Yes, and that's the danger: the next fix to the units would then break the retrained model. Fix the data, not the model.

</details>

---

## 7. Invariants Checklist

- [ ] Drift thresholds come from the no-drift null for each window size and bin count; bins have ≥ ~10 expected samples.
- [ ] Alerts fire on effect sizes (PSI, KS distance, sd shifts), not on p-values over large windows.
- [ ] Model-native signals (confidence PSI, deferral share, OOS/flag rate) are monitored per window, with sanity bounds independent of history.
- [ ] Embedding drift uses cluster shares, MMD or classifier two-sample tests, with references re-sampled and re-baselined after embedding migrations.
- [ ] At least one quality monitor uses a fixed, model-independent reference: the daily golden set through the serving path, or labelled samples.
- [ ] Labelling capacity is sized for both monitoring error bars and retraining needs, stratified toward drifted traffic.
- [ ] Every retrain passes a promotion gate: golden set through the serving path, paired champion comparison with per-class floors, shadow, canary with auto-rollback.
- [ ] Drift references reset only after a gated promotion.
- [ ] Step changes in single features after deploys are triaged as pipeline incidents; affected windows are quarantined from training data.
- [ ] Retraining combines a schedule (at the labelling cadence) with drift triggers (sequential detectors on rising signals).

---

## 8. References

1. S. Rabanser, S. Günnemann, Z. Lipton, *Failing Loudly: An Empirical Study of Methods for Detecting Dataset Shift*, NeurIPS 2019. https://arxiv.org/abs/1810.11953
2. J. Gama, I. Žliobaitė, A. Bifet, M. Pechenizkiy, A. Bouchachia, *A Survey on Concept Drift Adaptation*, ACM Computing Surveys 46(4), 2014. https://doi.org/10.1145/2523813
3. Z. Lipton, Y.-X. Wang, A. Smola, *Detecting and Correcting for Label Shift with Black Box Predictors*, ICML 2018. https://arxiv.org/abs/1802.03916
4. A. Gretton, K. Borgwardt, M. Rasch, B. Schölkopf, A. Smola, *A Kernel Two-Sample Test* (MMD), JMLR 13, 2012. https://jmlr.org/papers/v13/gretton12a.html
5. E. S. Page, *Continuous Inspection Schemes* (CUSUM), Biometrika 41(1–2), 1954. https://doi.org/10.1093/biomet/41.1-2.100
6. A. Bifet, R. Gavaldà, *Learning from Time-Changing Data with Adaptive Windowing* (ADWIN), SIAM SDM 2007. https://doi.org/10.1137/1.9781611972771.42
7. B. Yurdakul, *Statistical Properties of Population Stability Index*, PhD dissertation, Western Michigan University, 2018. https://scholarworks.wmich.edu/dissertations/3208
8. J. Kirkpatrick et al., *Overcoming Catastrophic Forgetting in Neural Networks* (EWC), PNAS 2017. https://arxiv.org/abs/1612.00796
9. S. Shankar, R. Garcia, J. Hellerstein, A. Parameswaran, *Operationalizing Machine Learning: An Interview Study*, 2022. https://arxiv.org/abs/2209.09125
10. Google Cloud, *MLOps: Continuous delivery and automation pipelines in machine learning*. https://cloud.google.com/architecture/mlops-continuous-delivery-and-automation-pipelines-in-machine-learning
11. A. Ng, *Machine Learning in Production* (DeepLearning.AI, Coursera): data drift, concept drift, the deployment and monitoring loop. https://www.coursera.org/learn/introduction-to-machine-learning-in-production
12. S. Larson et al., *An Evaluation Dataset for Intent Classification and Out-of-Scope Prediction* (CLINC150), EMNLP 2019. https://aclanthology.org/D19-1131/
