# 06.3 · Andrew Ng's Error Analysis, Bias/Variance in AI Systems & Calibrating LLM-as-a-Judge

> **Folder 06 · Evaluation Statistics, Error Analysis & LLM-as-a-Judge**
> **Measured on:** NumPy 2.5.4 and scikit-learn 1.9.1, the real CLINC150 router (LR on MiniLM embeddings), real SciFact runs from 06.2, and a seeded judge simulation with explicit, swappable flaws. Windows 11.
> **Design sources:** Ng (*Machine Learning Yearning*; the Coursera ML course's ceiling analysis; *Agentic AI*; The Batch on evals and error analysis), Cohen (κ, 1960), Zheng et al. (MT-Bench judge biases, 2023), Shankar et al. (validating validators, 2024), Rogan & Gladen (prevalence correction, 1978), Angelopoulos et al. (prediction-powered inference, 2023). Full list in §8.

---

## 0. Orientation: Look at the Errors Before You Touch the System

Ng's most repeated advice is also the most ignored: **before changing anything, look at a sample of the errors, tag them, and count.** Teams skip it because it feels slow, then spend weeks on a fix for the 5% bucket. This file makes the method concrete, applies the bias/variance lens to LLM systems, and treats an LLM judge as what it is: **a measurement instrument with its own error rate**. Measured results:

- **Error-analysis spreadsheet on the real router:** 171 validation errors, auto-tagged. OOS-accepted (26.9%) and sibling-intent confusion (23.4%) are the two named buckets that matter. "Very short query", which teams often suspect, is only 4.7%. The largest bucket, "other, low confidence" at 28.1%, is the auto-tagger admitting it doesn't know, and that's where a human has to read.
- **Learning curve:** training error stays at 0.00–0.27% at every size, and validation error falls from 12.9% to 4.0% as data grows 20×. This is a variance problem, and more data is still paying off.
- **Ceiling analysis on SciFact** (BM25 top-50 → MiniLM re-ordering): a perfect re-ranker would add **+0.212 nDCG@10**, perfect stage-1 recall only **+0.043**. Fund stage 2.
- **The judge as an instrument:** the simulated judge agrees with humans 70% of the time, which sounds fine, but that's **κ = 0.43**, against human-human κ = 0.71. Its raw pass rate is **0.655 vs the humans' 0.400**. Platt calibration on 600 human labels brings the expected pass rate to **0.421**. It also prefers longer answers (pass rate 0.87 → 1.00 across length quartiles at fixed quality) and the first-shown answer in pairwise mode (55.1%).

### The backend-engineer bridge

| You already know | Error-analysis / judge equivalent |
|---|---|
| Triage an incident queue by root-cause tag before fixing | **Error-analysis spreadsheet**: tag, count, fix the biggest bucket |
| Profiling before optimizing | **Ceiling analysis**: measure each stage's headroom before investing |
| Capacity problem vs config problem | **Bias** (the model can't fit) vs **variance** (it fits the wrong thing) |
| A monitoring probe that's itself flaky | **LLM judge**: an instrument whose error must be measured |
| Canary checks validated against known-good responses | **Judge calibration against human labels** |
| Measurement error in metrics (sampling, clock skew) | **Judge leniency and bias correction** |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 The error-analysis spreadsheet | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Tagging, counting, and choosing the fix by size × fixability | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Bias, variance, and avoidable bias against human-level performance | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Learning curves: reading and extrapolating | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Bias and variance in LLM workflows: prompting, RAG, fine-tuning | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Ceiling analysis for multi-stage pipelines | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 LLM-as-a-judge as an instrument: agreement and Cohen's κ | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Judge biases: leniency, verbosity, position, self-preference | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 Correcting judge-based estimates: calibration, Rogan–Gladen, PPI | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 How many human labels: sizing the judge-validation set | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.11 Rubrics, pointwise vs pairwise, and binary vs Likert | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.12 Latent-truth models (Dawid–Skene) and item response theory for benchmarks | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 The error-analysis spreadsheet `[MUST-KNOW: Core AI Engineer Edge]`

The procedure, as Ng teaches it in *Machine Learning Yearning* and revisits for agentic systems:

1. Take ~100 (or all, if fewer) **misclassified examples from the dev set**, not the test set, which stays untouched.
2. One row per error: the input, the prediction, the label, and the intermediate outputs of each component (retrieved chunks, tool calls, the router's confidence).
3. Add **tag columns** for candidate causes, and tick every tag that applies (tags aren't exclusive).
4. Count. The shares tell you the **maximum improvement** each fix could deliver.

```text
| # | input                                      | true -> pred           | conf | oos-acc | sibling | short | label? | notes                  |
|---|--------------------------------------------|------------------------|------|---------|---------|-------|--------|------------------------|
| 1 | how do i ask about the weather in chinese  | translate -> weather   | 0.73 |         |         |       |        | keyword "weather" wins |
| 2 | make an eft to my savings from my checking | transfer -> balance    | 0.23 |         |         |       |        | rare term "eft"        |
| 3 | set 60 minutes for oven please             | timer -> cook_time     | 0.45 |         |   ✓?    |       |   ✓?   | arguably cook_time     |
| … |                                            |                        |      |         |         |       |        |                        |
|   | COUNT                                      |                        |      |   46    |   40    |   8   |  ...   |                        |
```

The **ceiling principle**: if a bucket holds 23% of errors, a perfect fix for it removes at most 23% of errors. On 171 errors in 3,100 dev examples (5.5% error rate), fixing all sibling confusions would take the router to at most 4.2% error. Fixing a 4.7% bucket would move it to 5.3% at best. That arithmetic stops teams from optimizing the wrong thing.

### 1.2 Tagging, counting, and choosing the fix by size × fixability `[MUST-KNOW: Core AI Engineer Edge]`

Listing §3.1, section 1, auto-tags every validation error of the real router with simple rules (true class is OOS; predicted OOS; predicted the true class's nearest-centroid neighbour; ≤ 3 words; confidence < 0.5):

| Tag | Count | Share | Likely fix | Cost |
|---|---|---|---|---|
| other, low confidence | 48 | 28.1% | Unknown: **read these** | (reading time) |
| OOS routed to an intent | 46 | 26.9% | OOS gate on similarity/energy (02.3, 03.3) | Low |
| sibling intent | 40 | 23.4% | Contrastive examples, merge intents with slots | Medium |
| other, confident (check the label) | 23 | 13.5% | Audit labels, fix data | Low |
| very short query (≤ 3 words) | 8 | 4.7% | Clarifying question, context features | Medium |
| in-scope rejected as OOS | 6 | 3.5% | Threshold trade-off with OOS recall | Low |

Two lessons the numbers teach:

- **Automatic tags are hypotheses, not diagnoses.** The biggest bucket is the auto-tagger's residual ("other, low confidence"). Rules give you the fast first cut. Reading 30–50 of the residual rows is what produces new tags (in the example rows: keyword collisions like "weather" inside a translate request, rare vocabulary like "eft"). Ng's advice to *eyeball* the dev set is about exactly this.
- **Prioritize by share × fixability ÷ cost.** OOS-accepted is both large and cheap (a gate, no new labels). It goes first, even though "sibling" is nearly as large.
- **Some "errors" are label noise.** "set 60 minutes for oven please" labelled `timer`, predicted `cook_time`, is arguably either. The "confident" bucket (13.5%) is where label audits pay off, and fixing labels in the *dev set* changes what you measure. Ng's guidance: apply the same correction process to dev and test, and consider examples the system got right as well as wrong, so the label fixes don't bias the metric.

### 1.3 Bias, variance, and avoidable bias against human-level performance `[MUST-KNOW: Core AI Engineer Edge]`

Ng decomposes error with three reference points:

```text
human-level (≈ Bayes) error ── avoidable bias ──▶ training error ── variance ──▶ dev error ── (data mismatch) ──▶ test/prod error
```

- **Avoidable bias** = training error − human-level error. If it's large, the model can't fit what's learnable: use a bigger or better model class, better features, or train longer.
- **Variance** = dev error − training error. If it's large, the model fits training data that doesn't generalize: get more data, regularize, augment, or simplify.
- **Data mismatch** = test/production error − dev error. The dev set isn't the deployment distribution (06.1 §4.3, 07.3).

Human-level performance matters because it tells you how much bias is avoidable. In §3.1 the two human annotators of the judge simulation disagree on 14.3% of items. If that were your task's human-level error, a system at 15% error would have almost no avoidable bias, and the remaining fixes would be about data and evaluation, not model capacity.

### 1.4 Learning curves: reading and extrapolating `[MUST-KNOW: Core AI Engineer Edge]`

Listing §3.1, section 2, trains the same LR head on 5, 10, 25, 50 and 100 examples per intent:

| Training rows | Train error | Val error | Gap (variance) |
|---|---|---|---|
| 750 | 0.13% | 12.87% | 12.73 |
| 1,500 | 0.00% | 8.60% | 8.60 |
| 3,750 | 0.11% | 6.47% | 6.36 |
| 7,500 | 0.21% | 4.87% | 4.65 |
| 15,000 | 0.27% | 4.03% | 3.77 |

```text
error
 13% ┤●                                  ● val error: falling, not yet flat
     │
  9% ┤   ●
  6% ┤        ●
  5% ┤              ●
  4% ┤                    ●   ·  ·  (each doubling of data: ×0.83 at the last step)
     │
  0% ┼■───■────■─────■─────■──────── train rows (log)
      750  1.5k 3.75k 7.5k  15k      ■ train error ≈ 0 throughout
```

**Reading it:** training error ≈ 0 everywhere, so no measurable bias on the training distribution. The gap is all variance, and it's still shrinking with every doubling. The last doubling cut val error by 17% (4.87 → 4.03). Fitting a power law to the tail suggests another doubling would bring it to roughly 3.3–3.5%. ⚠ That's an extrapolation, not a measurement. Then compare the cost: labelling 15,000 more queries vs a regularization sweep (02.1 §1.8) vs the OOS gate from §1.2. Curves tell you *whether* data helps. Error analysis tells you *which* data.

When the curve **flattens with a large gap**, more of the same data won't help. Look for data mismatch, label noise, or features the model can't see. When **training error is high**, you're bias-limited and more data won't help at all.

### 1.5 Bias and variance in LLM workflows: prompting, RAG, fine-tuning `[MUST-KNOW: Core AI Engineer Edge]`

Ng's progression for improving an LLM application runs from cheapest to most expensive: prompting → RAG → fine-tuning → pre-training. The bias/variance lens maps onto it. This mapping is this KB's synthesis of Ng's framework, not a quotation:

| LLM-system symptom | Diagnosis | Cheapest fix that targets it |
|---|---|---|
| Fails even on the dev examples you iterated the prompt on | **Bias**: the system can't do the task | Better instructions, examples, decomposition into steps (agentic workflow), a stronger model |
| Fails because it lacks facts (stale, private, long-tail knowledge) | **Bias from missing information** | **RAG**: give it the knowledge; check retrieval Recall@k first (06.2) |
| Knows the facts but the format, style, or domain behaviour is wrong, persistently | **Bias in behaviour** | Few-shot first; then **fine-tuning** (LoRA, 01.2) or a small specialized model |
| Great on the 20 prompt-iteration examples, worse on a fresh held-out set | **Variance: prompt overfitting** | A bigger dev set, a held-out test set, remove special-case instructions |
| Good on the eval set, bad in production | **Data mismatch** | Sample the eval from production traffic, plus drift monitoring (07.3) |

The **variance row is the one teams miss**. A prompt iterated against 20 examples, with a special-case instruction added for each failure, is a model with ~20 "parameters" fitted to 20 points. Its dev score is optimistic in exactly the way training error is. The defence is identical to classical ML: keep a held-out set you don't look at while iterating, and size the dev set so that differences you act on exceed its noise (06.1 §1.7: ±1.9 points at n = 1,000 and p ≈ 0.9; ±8 to ±14 points at n = 50, depending on p).

### 1.6 Ceiling analysis for multi-stage pipelines `[MUST-KNOW: Core AI Engineer Edge]`

From Ng's original ML course (the photo-OCR pipeline): for a pipeline A → B → C, replace A's output with ground truth and measure the end-to-end metric. Then replace A *and* B, and so on. Each step's gain is that component's **ceiling**: the most that perfecting it could buy.

Listing §3.1, section 3, does this on real SciFact runs with a two-stage pipeline: **BM25 retrieves 50 candidates → MiniLM re-orders them**.

| Replace with an oracle | nDCG@10 | Gain |
|---|---|---|
| Current pipeline | 0.6603 | |
| Oracle stage 2 (perfect order of the 50 candidates) | 0.8721 | **+0.2118** |
| Oracle stage 1 (all relevant docs in the 50), MiniLM order | 0.7035 | **+0.0432** |
| Both oracles | 1.0000 | +0.3397 |

Stage-1 Recall@50 is already 0.869, so the evidence is usually *there*. The ordering is what loses points. A quarter spent on "better retrieval recall" has a ceiling of +0.04; one spent on a better re-ranker has a ceiling of +0.21. The oracles' gains don't add up (0.21 + 0.04 < 0.34), because the stages interact: a perfect re-ranker benefits from extra recall. Report both the single swaps and the joint one.

For LLM pipelines the same method applies to agentic workflows: replace the retrieval step with gold documents, the tool-call step with the correct call, or the planner's plan with a human-written plan, and measure the final answer. This is how Ng's agentic-workflow guidance turns "the agent is bad" into "the planner is the bottleneck".

### 1.7 LLM-as-a-judge as an instrument: agreement and Cohen's κ `[MUST-KNOW: Core AI Engineer Edge]`

An LLM judge rates outputs (pass/fail, 1–5, A vs B) at scale. Before trusting its numbers, measure it against humans, the way you'd validate any instrument. **Raw agreement is misleading**, because two raters who both say "pass" most of the time agree a lot by chance:

```text
κ = (p_o − p_e) / (1 − p_e)        p_o = observed agreement
                                    p_e = p_A(pass)·p_B(pass) + p_A(fail)·p_B(fail)   (agreement expected by chance)
```

From listing §3.2, section 1:

| Pair | Agreement | κ |
|---|---|---|
| Human 1 vs human 2 | 0.857 | 0.706 |
| Judge vs human 1 | 0.698 | 0.429 |
| Judge vs human 2 | 0.710 | 0.444 |
| Always-pass vs human 1 | 0.411 | **0.000** |

**Human-human κ is the ceiling.** No judge can be validated beyond the humans' own agreement, because the reference itself is noisy. A judge with κ = 0.43 against a human-human κ of 0.71 is a weak instrument: it's useful for detecting large changes but not small ones. Common verbal scales (Landis & Koch: 0.41–0.60 "moderate", 0.61–0.80 "substantial") are conventions, not guarantees. What matters is whether the judge's error is small *relative to the deltas you need to detect*.

### 1.8 Judge biases: leniency, verbosity, position, self-preference `[MUST-KNOW: Core AI Engineer Edge]`

Zheng et al. (MT-Bench, 2023) documented the main judge biases. The simulation in §3.2 builds them in explicitly so the audits can be shown working:

- **Leniency.** The judge passes 0.655 of answers; humans pass 0.400. Any "pass rate" from this judge overstates quality by ~25 points. It's a *constant* bias, so *differences* between two systems may survive it, but absolute claims don't.
- **Verbosity.** In a band of borderline answers (0 < quality < 0.6) where quality is independent of length by construction, the judge's pass rate rises **0.870 → 0.942 → 0.971 → 1.000** across length quartiles, while humans stay around 0.44–0.59. **Audit:** bin by length (or any nuisance variable) at matched human labels, and check whether the judge's pass rate trends. A prompt change that makes answers longer will "improve" the judged score without improving quality.
- **Position (pairwise mode).** The judge picks the first-shown answer 55.1% of the time (50% expected). Only **80.8%** of verdicts survive swapping the order. Among stable verdicts, accuracy is **0.956**, so the fix is to judge both orders and keep agreeing verdicts (treat disagreements as ties), or score each answer separately.
- **Self-preference.** LLM judges can recognize and favour outputs from their own model family (Panickssery et al., 2024). When the judge and one candidate share a family, audit per-system agreement with humans, or use a judge from a different family.

### 1.9 Correcting judge-based estimates: calibration, Rogan–Gladen, PPI `[GOOD-TO-KNOW: Architectural Literacy]`

If you know how the judge errs, you can correct the *aggregate* even when individual verdicts are wrong:

- **Calibration of a judge score.** If the judge emits a score (logit, 1–10, or a probability), fit p(human pass | score) with Platt scaling on held-out human labels and average the calibrated probabilities. In §3.2: raw judge pass rate 0.655, Platt-calibrated estimate **0.421**, human truth 0.400.
- **Rogan–Gladen** (from epidemiology, for binary verdicts). With the judge's sensitivity Se and specificity Sp measured against humans:

```text
true pass rate ≈ (observed pass rate + Sp − 1) / (Se + Sp − 1)
```

  It's valid when the judge's error rates are the same on the new system as on the validation set. That's exactly what changes when the new system's outputs look different, so re-validate per system.
- **Prediction-powered inference** (Angelopoulos et al., 2023) combines many cheap judge labels with a small set of human labels and gives an estimate with a **valid confidence interval**: the judge's mean plus a "rectifier" estimated from the human-labelled subset. It's the principled version of "LLM labels at scale, humans audit a sample".

### 1.10 How many human labels: sizing the judge-validation set `[MUST-KNOW: Core AI Engineer Edge]`

To estimate the judge's agreement with humans to ±h at 95%:

```text
n ≈ 1.96² · a(1 − a) / h²         a = expected agreement
```

At a = 0.70 (listing §3.2, section 4): **±5 points needs 324 labels, ±3 needs 900, ±2 needs 2,024.** Two practical implications:

1. **Validate on the slice you'll use the judge on.** Agreement measured on easy outputs doesn't transfer to borderline ones. Stratify the human labels by the judge's score band and by system, and weight the strata back.
2. **The judge's error limits the deltas it can see.** If the judge disagrees with humans on 30% of items and the system change flips 3% of outputs, the judge's errors can bury the signal unless they're independent of the change. Prefer judging *pairs* (old vs new on the same input) with position-swap, and measure the judge's accuracy specifically on items where the two systems differ.

### 1.11 Rubrics, pointwise vs pairwise, and binary vs Likert `[GOOD-TO-KNOW: Architectural Literacy]`

Design choices that consistently improve judge reliability in practice:

- **Binary, criterion-specific questions over 1–10 scores.** "Does the answer state a refund deadline that matches the policy document? yes/no" beats "rate helpfulness 1–10". Binary verdicts are easier to validate (κ, Se/Sp) and to act on.
- **One judge per failure mode** found in error analysis, rather than one omnibus "quality" judge. The error-analysis tags (§1.2) *are* the judge rubric.
- **Reasoning before the verdict**, with a few labelled examples from the human set, especially borderline ones.
- **Pairwise for "is B better than A", pointwise for "does this pass the bar".** Pairwise is more sensitive to small differences but needs position-swap and gives no absolute level.
- **Version the judge** (model ID, prompt, examples) like code. A judge change is a metric change and invalidates comparisons across versions.

Shankar et al. (2024) found that evaluation criteria themselves drift as people grade outputs ("criteria drift"). Expect the rubric to change during the first labelling rounds, and re-validate afterwards.

### 1.12 Latent-truth models (Dawid–Skene) and item response theory for benchmarks `[SKIP: Academic/Research Only]`

Dawid–Skene estimates each rater's confusion matrix and the latent true labels jointly with EM. Item response theory models item difficulty and system ability for benchmark design. Both are elegant ways to aggregate noisy raters. In practice, a few humans with an adjudication step plus a validated judge covers production needs.

---

## 2. Where It Beats an LLM in Production

**1. Cheap classical tooling does the error analysis that makes LLM spend efficient.** The auto-tagger in §3.1 is a few `if` statements over the router's outputs, centroid similarities and query lengths. It ran on all 171 errors in milliseconds and found the cheap, large fix (an OOS gate) before anyone paid for an LLM-based analysis. Clustering failed queries (03.1) and tagging them with rules or a small classifier beats asking an LLM to "analyze the failures" for the first pass: it's deterministic, free and repeatable. Use the LLM to *propose* tags for the residual bucket, then confirm by reading.

**2. A calibrated cheap scorer can be a better judge than an LLM for narrow criteria.** Many judge criteria are classification problems with labels you already have: "is this answer grounded in the context" (an NLI cross-encoder), "does it contain PII" (a guardrail head), "is it in the right language" (a language-ID model), "does it match the required JSON schema" (a parser). For these, a small model gives a *score* with a full operating curve (06.1 §2), sub-10 ms latency, no position or verbosity bias, and a validation story built on standard metrics. Reserve LLM judges for criteria that genuinely need reading comprehension: correctness against a reference, tone, policy compliance.

**3. Human-label budgets go further with a judge, if the judge is measured.** The economics (06.2 §1.8: ~$0.50 per 6,000 judgments) only pay off when the judge's error is known. Then prediction-powered inference turns 300 human labels plus 10,000 judge labels into an estimate with a valid confidence interval (§1.9).

---

## 3. Production Code Blueprint

### 3.1 Error-analysis spreadsheet, learning curve, and ceiling analysis on real systems

```python
"""error_analysis_and_ceiling.py - Andrew Ng's error-analysis spreadsheet and ceiling analysis, on real systems.

  1. Router (CLINC150 + OOS): tag every validation error automatically, count the tags -> what to fix first.
  2. Bias vs variance: training-set and validation error as the training set grows (learning curve).
  3. Ceiling analysis of a 2-stage retrieval pipeline (SciFact: BM25 top-50 -> MiniLM re-orders the candidates):
     replace each stage with an oracle, keep the other stage as is, and measure the end-to-end gain
     -> which stage is worth engineering time.
"""
import json
import math
import os
from collections import Counter

import numpy as np
from sklearn.linear_model import LogisticRegression

DATA = os.environ["KB_DATA"]
Z = np.load(os.path.join(DATA, "clinc_minilm.npz"))
meta = json.load(open(os.path.join(DATA, "clinc_meta.json"), encoding="utf-8"))
labels = meta["labels"] + ["oos"]
OOS = 150
Xtr = np.vstack([Z["X_train"], Z["X_oos_train"]])
ytr = np.r_[Z["y_train"], np.full(len(Z["X_oos_train"]), OOS)]
Xva = np.vstack([Z["X_val"], Z["X_oos_val"]])
yva = np.r_[Z["y_val"], np.full(len(Z["X_oos_val"]), OOS)]
Tva = meta["texts"]["val"] + meta["texts"]["oos_val"]
clf = LogisticRegression(C=10, max_iter=3000).fit(Xtr, ytr)
P = clf.predict_proba(Xva)
pred = P.argmax(1)
cent = np.stack([Xtr[ytr == c].mean(0) for c in range(151)])
cent /= np.linalg.norm(cent, axis=1, keepdims=True)
nearest_other = np.argsort(-(cent @ cent.T), axis=1)[:, 1]          # each intent's most similar intent


def tag(i):
    t, q, conf = yva[i], pred[i], P[i].max()
    if t == OOS:
        return "oos-accepted (OOS routed to an intent)"
    if q == OOS:
        return "in-scope rejected as OOS"
    if nearest_other[t] == q or nearest_other[q] == t:
        return "sibling intent (nearest-centroid neighbour)"
    if len(Tva[i].split()) <= 3:
        return "very short query (<= 3 words)"
    if conf < 0.5:
        return "other, low confidence"
    return "other, confident (check the label)"


err = np.flatnonzero(pred != yva)
tags = Counter(tag(i) for i in err)
print(f"== 1. error-analysis spreadsheet: {len(err)} validation errors of {len(yva)} ==")
print(f"{'tag':46s} {'count':>5} {'share':>6}")
for k, v in sorted(tags.items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"{k:46s} {v:>5} {v / len(err):>6.1%}")
print("example rows (true -> predicted, confidence, text):")
for i in err[:5]:
    print(f"  {labels[yva[i]]:>20s} -> {labels[pred[i]]:<20s} {P[i].max():.2f}  '{Tva[i]}'")

print("\n== 2. bias vs variance: learning curve (in-scope intents, LR C=10) ==")
rng = np.random.default_rng(171)
print(f"{'train rows':>10} {'train err':>9} {'val err':>8} {'gap':>6}")
curve = []
for k in (5, 10, 25, 50, 100):
    idx = np.concatenate([rng.choice(np.flatnonzero(Z["y_train"] == c), k, replace=False) for c in range(150)])
    m = LogisticRegression(C=10, max_iter=3000).fit(Z["X_train"][idx], Z["y_train"][idx])
    tr_e, va_e = 1 - m.score(Z["X_train"][idx], Z["y_train"][idx]), 1 - m.score(Z["X_val"], Z["y_val"])
    curve.append((tr_e, va_e))
    print(f"{len(idx):>10,} {tr_e:>9.4f} {va_e:>8.4f} {va_e - tr_e:>6.4f}")
print("training error ~0 at every size (no avoidable bias on the training set); the gap shrinks with data (variance)")
assert curve[-1][1] < curve[0][1]

print("\n== 3. ceiling analysis: stage 1 (BM25 top-50) -> stage 2 (MiniLM re-orders the 50) on SciFact ==")
R = np.load(os.path.join(DATA, "scifact_runs.npz"))
meta_r = json.load(open(os.path.join(DATA, "scifact_runs.json")))
doc_ids = [json.loads(l)["_id"] for l in open(os.path.join(os.environ["KB_DL"], "scifact", "x", "scifact", "corpus.jsonl"), encoding="utf-8")]
id_pos = {d: i for i, d in enumerate(doc_ids)}
qids = [str(q) for q in R["test_q"]]


def ndcg10(gains, n_rel):
    return float(np.sum(np.asarray(gains[:10]) / np.log2(np.arange(2, 2 + len(gains[:10])))) /
                 sum(1 / math.log2(r + 2) for r in range(min(10, n_rel))))


def stage2(cands, dense_top):
    """MiniLM order: dense rank inside its top-100; anything deeper keeps its stage-1 order behind those."""
    dpos = {int(d): r for r, d in enumerate(dense_top)}
    return sorted(cands, key=lambda d: (dpos.get(d, 10_000), cands.index(d)))


rows = {"current: BM25 top-50 -> MiniLM order": [], "oracle stage 2 (perfect order of the 50)": [],
        "oracle stage 1 (all relevant in the 50) -> MiniLM": [], "both oracles": []}
recall50 = []
for q, bm, dn in zip(qids, R["top_0"], R["top_1"]):
    rel = {id_pos[d] for d in meta_r["qrels"][q]}
    cands = [int(d) for d in bm[:50]]
    recall50.append(len(rel & set(cands)) / len(rel))
    missing = [d for d in rel if d not in cands]                     # oracle stage 1: swap them in for the
    keep = [d for d in cands if d in rel] + [d for d in cands if d not in rel]   # lowest-ranked non-relevant ones
    full = [d for d in cands if d in set(keep[:50 - len(missing)])] + missing
    for name, c in (("current: BM25 top-50 -> MiniLM order", cands),
                    ("oracle stage 1 (all relevant in the 50) -> MiniLM", full)):
        rows[name].append(ndcg10([1 if d in rel else 0 for d in stage2(c, dn)], len(rel)))
    rows["oracle stage 2 (perfect order of the 50)"].append(ndcg10(sorted([1 if d in rel else 0 for d in cands], reverse=True), len(rel)))
    rows["both oracles"].append(1.0)
base = np.mean(rows["current: BM25 top-50 -> MiniLM order"])
print(f"stage-1 Recall@50 {np.mean(recall50):.4f}")
print(f"{'replace with an oracle':52s} {'nDCG@10':>8} {'gain':>7}")
for k, v in rows.items():
    print(f"{k:52s} {np.mean(v):>8.4f} {np.mean(v) - base:>+7.4f}")
gain_rr = np.mean(rows["oracle stage 2 (perfect order of the 50)"]) - base
gain_ret = np.mean(rows["oracle stage 1 (all relevant in the 50) -> MiniLM"]) - base
print(f"headroom: a perfect stage 2 adds {gain_rr:+.4f}; perfect stage-1 recall adds {gain_ret:+.4f} -> "
      f"{'fund the re-ranker (stage 2) first' if gain_rr > gain_ret else 'fund retrieval (stage 1) first'}")
assert gain_rr > 0 and gain_ret > 0
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. error-analysis spreadsheet: 171 validation errors of 3100 ==
tag                                            count  share
other, low confidence                             48  28.1%
oos-accepted (OOS routed to an intent)            46  26.9%
sibling intent (nearest-centroid neighbour)       40  23.4%
other, confident (check the label)                23  13.5%
very short query (<= 3 words)                      8   4.7%
in-scope rejected as OOS                           6   3.5%
example rows (true -> predicted, confidence, text):
             translate -> weather              0.73  'how do i ask about the weather in chinese'
              transfer -> balance              0.23  'make an eft to my savings from my checking account'
                 timer -> cook_time            0.45  'set 60 minutes for oven please'
            definition -> exchange_rate        0.49  'define monetary for me please'
       meaning_of_life -> oos                  0.34  'do you think we have a higher calling'

== 2. bias vs variance: learning curve (in-scope intents, LR C=10) ==
train rows train err  val err    gap
       750    0.0013   0.1287 0.1273
     1,500    0.0000   0.0860 0.0860
     3,750    0.0011   0.0647 0.0636
     7,500    0.0021   0.0487 0.0465
    15,000    0.0027   0.0403 0.0377
training error ~0 at every size (no avoidable bias on the training set); the gap shrinks with data (variance)

== 3. ceiling analysis: stage 1 (BM25 top-50) -> stage 2 (MiniLM re-orders the 50) on SciFact ==
stage-1 Recall@50 0.8694
replace with an oracle                                nDCG@10    gain
current: BM25 top-50 -> MiniLM order                   0.6603 +0.0000
oracle stage 2 (perfect order of the 50)               0.8721 +0.2118
oracle stage 1 (all relevant in the 50) -> MiniLM      0.7035 +0.0432
both oracles                                           1.0000 +0.3397
headroom: a perfect stage 2 adds +0.2118; perfect stage-1 recall adds +0.0432 -> fund the re-ranker (stage 2) first

ALL ASSERTIONS PASSED
```

### 3.2 Treating an LLM judge as a measurement instrument

The judge here is **simulated, with explicit, seeded flaws** (leniency, verbosity, position), so each audit can be shown detecting a known effect. The computations are the ones you'd run on real data: replace `h1`, `h2`, `judge` and `judge_logit` with your human labels and judge outputs.

```python
"""llm_judge_calibration.py - treating an LLM-as-a-judge like any other measurement instrument.

A seeded simulation of 1,200 answers rated pass/fail by two human annotators and by an LLM judge with
realistic flaws (a leniency bias, a verbosity bias, and a position bias in pairwise mode). Swap in your own
labels and judge outputs; every computation below stays the same.
  1. Agreement: raw accuracy vs Cohen's kappa; human-human agreement as the ceiling.
  2. The judge's pass rate vs the human pass rate, and a correction (Platt on held-out human labels).
  3. Bias audits: verbosity (pass rate by answer length) and position (swap the pair order).
  4. How many human labels you need to estimate the judge's accuracy within +-2 to +-5 points.
"""
import numpy as np
from sklearn.linear_model import LogisticRegression

rng = np.random.default_rng(181)
n = 1200
quality = rng.normal(0, 1, n)                                       # latent answer quality
length = rng.lognormal(5, 0.6, n)                                   # answer length in tokens
truth = quality > 0.3                                               # what an ideal rater would say (about 38% pass)
h1 = truth ^ (rng.random(n) < 0.08)                                 # two humans, 8% independent noise each
h2 = truth ^ (rng.random(n) < 0.08)
judge_logit = 2.0 * quality + 0.9 + 0.6 * (np.log(length) - 5) + rng.normal(0, 0.8, n)   # lenient + verbosity bias
judge = judge_logit > 0


def kappa(a, b):
    po = np.mean(a == b)
    pe = np.mean(a) * np.mean(b) + np.mean(~a) * np.mean(~b)
    return (po - pe) / (1 - pe)


print("== 1. agreement ==")
print(f"{'pair':18s} {'agreement':>9} {'Cohen kappa':>11}")
for name, a, b in (("human 1 vs human 2", h1, h2), ("judge vs human 1", judge, h1), ("judge vs human 2", judge, h2)):
    print(f"{name:18s} {np.mean(a == b):>9.3f} {kappa(a, b):>11.3f}")
always = np.ones(n, bool)
print(f"{'always-pass vs h1':18s} {np.mean(always == h1):>9.3f} {kappa(always, h1):>11.3f}   <- raw agreement can look fine at kappa 0")

print("\n== 2. pass rates and correction ==")
fit, test = slice(0, 600), slice(600, n)
platt = LogisticRegression().fit(judge_logit[fit, None], h1[fit])
p_cal = platt.predict_proba(judge_logit[test, None])[:, 1]
print(f"human pass rate (test half) {h1[test].mean():.3f}; raw judge pass rate {judge[test].mean():.3f}; "
      f"Platt-calibrated expected pass rate {p_cal.mean():.3f}")
assert abs(p_cal.mean() - h1[test].mean()) < abs(judge[test].mean() - h1[test].mean())

print("\n== 3a. verbosity audit: pass rate by answer-length quartile, inside one narrow true-quality band ==")
mid = (quality > 0.0) & (quality < 0.6)                             # borderline answers: the pass line (0.3) is inside
q = np.quantile(length[mid], [0.25, 0.5, 0.75])
bins = np.digitize(length[mid], q)
print(f"{mid.sum()} borderline answers (0 < quality < 0.6); quality does not depend on length by construction")
print(f"{'length quartile':>15} {'judge pass':>10} {'human pass':>10}")
vq = []
for b in range(4):
    m = bins == b
    vq.append(judge[mid][m].mean())
    print(f"{b + 1:>15} {vq[-1]:>10.3f} {h1[mid][m].mean():>10.3f}")
print("humans pass about half of the band at every length; the judge passes most of it, and more as answers get longer")
assert vq[3] > vq[0] + 0.05

print("\n== 3b. position audit (pairwise mode: 'which answer is better?') ==")
pairs = rng.integers(0, n, (2000, 2))
better_true = quality[pairs[:, 0]] > quality[pairs[:, 1]]


def pairwise(a, b, first_bonus=0.35):
    return (2.0 * quality[a] + first_bonus + rng.normal(0, 0.8, len(a))) > (2.0 * quality[b] + rng.normal(0, 0.8, len(a)))


ab = pairwise(pairs[:, 0], pairs[:, 1])                              # True = picks the answer shown first
ba = pairwise(pairs[:, 1], pairs[:, 0])
consistent = ab != ba                                                # the verdict flips with the order -> consistent
print(f"picks the FIRST-shown answer {(np.mean(ab) + np.mean(ba)) / 2:.3f} of the time (0.5 expected); verdict stable under order swap "
      f"{np.mean(consistent):.3f}; accuracy when stable {np.mean(ab[consistent] == better_true[consistent]):.3f}")
print("fix: judge both orders and keep agreeing verdicts (or score each answer separately)")

print("\n== 4. human labels needed to estimate the judge's accuracy within +-h (95%, normal approximation) ==")
acc = np.mean(judge == h1)
for half_width in (0.05, 0.03, 0.02):
    print(f"  +-{half_width:.2f}: n >= {int(np.ceil(1.96 ** 2 * acc * (1 - acc) / half_width ** 2))}  (at accuracy {acc:.3f})")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. agreement ==
pair               agreement Cohen kappa
human 1 vs human 2     0.857       0.706
judge vs human 1       0.698       0.429
judge vs human 2       0.710       0.444
always-pass vs h1      0.411       0.000   <- raw agreement can look fine at kappa 0

== 2. pass rates and correction ==
human pass rate (test half) 0.400; raw judge pass rate 0.655; Platt-calibrated expected pass rate 0.421

== 3a. verbosity audit: pass rate by answer-length quartile, inside one narrow true-quality band ==
277 borderline answers (0 < quality < 0.6); quality does not depend on length by construction
length quartile judge pass human pass
              1      0.870      0.536
              2      0.942      0.594
              3      0.971      0.435
              4      1.000      0.557
humans pass about half of the band at every length; the judge passes most of it, and more as answers get longer

== 3b. position audit (pairwise mode: 'which answer is better?') ==
picks the FIRST-shown answer 0.551 of the time (0.5 expected); verdict stable under order swap 0.808; accuracy when stable 0.956
fix: judge both orders and keep agreeing verdicts (or score each answer separately)

== 4. human labels needed to estimate the judge's accuracy within +-h (95%, normal approximation) ==
  +-0.05: n >= 324  (at accuracy 0.698)
  +-0.03: n >= 900  (at accuracy 0.698)
  +-0.02: n >= 2024  (at accuracy 0.698)

ALL ASSERTIONS PASSED
```

### 3.3 A judge-validation record worth storing

```python
@dataclass(frozen=True)
class JudgeValidation:
    judge_id: str                  # model ID + prompt hash + few-shot set hash
    task: str                      # one criterion, e.g. "refund-deadline-correct"
    n_human: int                   # human-labelled items, stratified by system and score band
    human_human_kappa: float       # the ceiling
    judge_human_kappa: float
    sensitivity: float             # P(judge pass | human pass)
    specificity: float             # P(judge fail | human fail)
    per_system_kappa: dict         # system -> kappa; flags self-preference / style bias
    length_trend: float            # slope of judge pass rate vs length at matched human labels
    position_flip_rate: float      # pairwise only: share of verdicts that change under order swap
    valid_until: str               # re-validate on judge, prompt or system change
```

Every judged metric in a dashboard should link to the `JudgeValidation` it relies on. A number from an unvalidated judge is an opinion.

---

## 4. The Andrew Ng Lens: Evaluation-Driven Development, Done Honestly

### 4.1 The loop

Ng's *Agentic AI* course and his letters in The Batch describe the loop that makes AI products improve instead of churn:

```text
build a quick end-to-end version ──▶ collect outputs on a dev set ──▶ error analysis (tag & count)
          ▲                                                                   │
          │                                                                   ▼
   re-measure on the SAME evals ◀── fix the biggest fixable bucket ◀── write an eval for that bucket
```

Two details make it work. First, **evals are written for the failure modes you found**, not for abstract quality. Each error-analysis tag becomes a targeted eval (a regex check, a classifier, or a validated binary judge). Second, **the eval is fixed while you iterate**, so improvements are measured against a stable ruler.

### 4.2 Bias/variance as the triage question

Every week, the error-analysis table and the learning curve answer one question: are we bias-limited (the system can't do it, so change the model, the workflow decomposition, or the knowledge it has via RAG) or variance-limited (it overfits what we tuned on, so more and fresher eval data, fewer special cases)? §1.5's table maps this onto the prompting → RAG → fine-tuning ladder, cheapest first.

### 4.3 Human-level performance as the reference

Ng uses human-level performance to estimate how much error is avoidable. For LLM products, the human-human κ on the judge task plays the same role for evaluation: if two expert reviewers agree only at κ = 0.7, a judge can't be validated beyond that, and a product metric based on it can't resolve differences smaller than the raters' disagreement. Measure it early. It sets the resolution of your whole evaluation stack.

### 4.4 The AI Engineering Skills Map: where this file sits

In this KB's skills map (README; our synthesis, since no canonical Ng document by that name exists), error analysis and judge calibration are the **"Evaluation and error analysis"** row. That's the skill that separates teams who ship improvements every week from teams who ship prompt changes and hope. Ng has repeatedly argued that disciplined error analysis is among the most valuable skills for AI engineering teams. It's also the one interviewers probe hardest at Staff level, because it can't be faked with vocabulary.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Weeks of work, metric unchanged | The fixed bucket was ~5% of errors | No error analysis before choosing the fix | Tag and count 100 dev errors first | Error-analysis table required in every project review |
| F2 | Auto-tags say "other" for a third of errors | Large residual bucket | Rules cover known causes only | Read 30–50 residual rows, add tags | Residual share tracked; target < 20% |
| F3 | Prompt "improves" on dev, regresses in production | Dev score up, held-out flat | Prompt overfitting (variance) | Bigger dev set; held-out test set; remove special cases | Held-out set never used while iterating |
| F4 | Quarter spent on the wrong pipeline stage | Small gain from the "fixed" stage | No ceiling analysis | Oracle-swap each stage, measure end-to-end | Ceiling table in the roadmap doc |
| F5 | Judge pass rate says 66%, users disagree | Judge leniency | Uncalibrated judge | Calibrate on human labels (Platt / Rogan–Gladen / PPI) | `JudgeValidation` record per judged metric |
| F6 | A prompt change "improves" judged quality | Answers got longer | Verbosity bias | Length-stratified audit at matched human labels | Length trend in the judge validation |
| F7 | Pairwise A/B judge favours whichever is shown first | Order-dependent verdicts | Position bias | Judge both orders; ties on disagreement | Position-flip rate in the validation |
| F8 | Judge favours one model's outputs | Per-system κ differs | Self-preference / style bias | Different-family judge; per-system validation | Per-system κ in the validation |
| F9 | Judge "validated" but useless for small changes | κ fine overall, deltas unresolved | Judge error ≫ the effect size | Pairwise judging on differing items; more human labels on them | Size the validation set for the deltas you need (§1.10) |
| F10 | Dev-set label fixes inflate the metric | Only errors were re-labelled | Biased correction | Re-check correct and incorrect items alike; apply to dev and test | Label-audit protocol |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Our RAG support bot is 70% accurate. What do you do first?"</b></summary>

**Initial Prompt.** A team asks for a plan to reach 85%.

**L5 Answer.** "Try a bigger model and better embeddings, then tune the prompt."

**Why L5 Fails in Production.** It picks fixes before knowing where the 30% of failures come from. Each of those fixes targets a different bucket, and two of them may be small.

**L7 Principal Defense.** "Error analysis first. Pull 100 failing dev conversations, one row each, with the retrieved chunks and the answer. Tag: was the needed document retrieved? Retrieved but ignored or misread? A wrong or stale document? An out-of-scope question? A bad label? Count. Then a ceiling analysis: answer accuracy with *gold* context tells me the generator's ceiling, and Recall@k tells me retrieval's. If, say, 55% of failures are 'evidence not retrieved', the next sprint is retrieval (hybrid search, chunking, a re-ranker, 04 and 06.2). If it's 'retrieved but misread', it's the prompt or the model. Each bucket gets a targeted eval, and we re-measure on the same set."

**Bar-Raiser Follow-ups.**
- *"Why 100 errors?"* It's enough to see any bucket above ~5% with a few examples, and it takes an afternoon. Go bigger only if the buckets are close.
- *"Who reads them?"* The engineers building the system, not only annotators. Reading the failures is how the team learns the problem.

</details>

<details><summary><b>Q2 · "Training error 0.3%, validation error 4%. What next?"</b></summary>

**Initial Prompt.** The CLINC learning curve from §3.1.

**L5 Answer.** "The model is overfitting, so make it simpler."

**Why L5 Fails in Production.** "Simpler" is one option. The curve says more: the gap is still shrinking with every doubling, so data is paying off. It also skips checking whether 4% is near the achievable floor.

**L7 Principal Defense.** "Training error near zero means there's no avoidable bias on the training distribution. The 3.8-point gap is variance. The curve hasn't flattened: the last doubling cut val error 17% (4.87 → 4.03), so more labelled data would help, and the extrapolation suggests ~3.3–3.5% from another doubling. I'd compare that with cheaper variance fixes, a regularization sweep on C and label noise cleanup, and with the error analysis. A quarter of the errors are OOS acceptance, which no amount of in-scope data fixes. So: the OOS gate first (cheap, large), then a C sweep, then targeted data for the sibling-intent pairs."

**Bar-Raiser Follow-ups.**
- *"How would you know you're near human-level?"* Have two people label 300 dev queries. Their disagreement rate estimates the noise floor.
- *"When does more data stop helping?"* When the val curve flattens with a gap still open. Then look for data mismatch or missing features.

</details>

<details><summary><b>Q3 · "Should we fine-tune or improve our RAG pipeline?"</b></summary>

**Initial Prompt.** An LLM answers questions about internal policies; accuracy is mediocre.

**L5 Answer.** "Fine-tune on our documents so the model knows them."

**Why L5 Fails in Production.** Fine-tuning is a poor way to inject facts that change: it's expensive to update, hard to attribute, and doesn't fix retrieval failures. The question is unanswerable without knowing *which* errors dominate.

**L7 Principal Defense.** "I'd diagnose with the bias/variance lens. Errors from *missing or stale facts* are an information problem, so RAG, and I'd check retrieval Recall@k first. Errors where the model *has* the right context but answers in the wrong format, tone or reasoning style, consistently, are behaviour bias. Few-shot examples first, then fine-tuning (LoRA on a few thousand examples) if the pattern is stable and high-volume. Errors that appear only on fresh queries after heavy prompt iteration are variance, and need a larger eval set and fewer special cases. Error analysis on 100 failures gives the split. In most enterprise Q&A, the dominant bucket is retrieval."

**Bar-Raiser Follow-ups.**
- *"When is fine-tuning clearly right?"* A narrow, high-volume task (classification, extraction, a fixed format) where a small fine-tuned model replaces a large prompted one: cheaper and faster (Folder 07).
- *"And both?"* Fine-tuning a model to *use* retrieved context better (RAFT-style) is real, but only after retrieval is measured to be good.

</details>

<details><summary><b>Q4 · "We'll use an LLM as the judge. How do you know it's right?"</b></summary>

**Initial Prompt.** A team proposes Claude-as-judge for answer correctness.

**L5 Answer.** "We checked 50 examples and it agreed with us 90% of the time."

**Why L5 Fails in Production.** Fifty examples give a ±8-point interval. Raw agreement isn't chance-corrected (an always-pass judge scored 41% agreement at κ = 0). And there's no check for leniency, verbosity, position or per-system bias.

**L7 Principal Defense.** "I'd validate it like an instrument. (1) Two humans label a stratified set, about 300+ items for ±5 points. Their κ is the ceiling (0.71 in §3.2). (2) Judge-human κ, sensitivity and specificity: 0.43 in the simulation, a weak instrument. (3) Bias audits: pass rate vs length at matched human labels, position-flip rate in pairwise mode, κ per system under test. (4) If its pass rate is offset (0.655 vs 0.400 here), report calibrated estimates (Platt: 0.421) or use PPI for intervals. All of that goes in a versioned validation record, and any judge model or prompt change re-runs it."

**Bar-Raiser Follow-ups.**
- *"Binary or 1–10?"* Binary, one criterion per judge, mapped to the error-analysis tags. It's easier to validate and to act on.
- *"Can the judge see the reference answer?"* Yes, for correctness. Reference-guided judging is much more reliable than free-form "is this good".

</details>

<details><summary><b>Q5 · "After our prompt change, the judged pass rate went from 60% to 66%. Ship it?"</b></summary>

**Initial Prompt.** A weekly eval report.

**L5 Answer.** "Six points is a clear win."

**Why L5 Fails in Production.** It ignores whether the change altered something the judge is biased by (length, style), whether 6 points is outside the noise, and whether the judge is calibrated in absolute terms.

**L7 Principal Defense.** "Three checks. (1) **Did the change alter a nuisance variable?** If average answer length rose, the verbosity audit applies: in §3.2 the judge's pass rate rises 13 points from the shortest to the longest quartile at fixed quality. Compare pass rates within length bins. (2) **Is it outside the noise?** Judge both versions on the same inputs and run a paired test on per-item verdicts (McNemar). (3) **Do humans agree on the items that changed?** Pull 100 items where the verdict flipped and have humans label them. That's where the judge's accuracy matters. If all three hold, ship. The absolute number ('66% pass') still needs calibration before anyone quotes it."

**Bar-Raiser Follow-ups.**
- *"Cheapest of the three?"* The length check: it needs no new labels.
- *"How do you stop this recurring?"* Put length-normalized and pairwise metrics in the standard eval report.

</details>

<details><summary><b>Q6 · "The pairwise judge prefers the new model 55% of the time. Is it better?"</b></summary>

**Initial Prompt.** An A-vs-B judge always shows the new model's answer first.

**L5 Answer.** "55% is above 50%, so yes."

**Why L5 Fails in Production.** In §3.2 a judge with *no* real preference picks the first-shown answer 55.1% of the time. The result is exactly what position bias predicts.

**L7 Principal Defense.** "The protocol is confounded: order and system are perfectly correlated. Re-run with both orders for every pair. Keep a verdict only if it's stable under the swap (80.8% were in §3.2, with 0.956 accuracy among those), and count flips as ties. Then the preference rate among stable verdicts, with a binomial CI, is the answer. Better still, randomize order *and* report the flip rate as a judge-health metric, because a high flip rate means the two systems are close or the judge is weak."

**Bar-Raiser Follow-ups.**
- *"Why not just randomize order?"* Randomizing removes the bias in expectation but adds noise. Both orders per pair removes it item by item.
- *"What about ties?"* Allow an explicit tie option. Forced choice inflates noise on near-equal pairs.

</details>

<details><summary><b>Q7 · "Where should we invest next quarter: retrieval or re-ranking?"</b></summary>

**Initial Prompt.** A two-stage search: BM25 top-50, then a re-ranker.

**L5 Answer.** "Retrieval: if the document isn't retrieved, nothing else matters."

**Why L5 Fails in Production.** True as a principle, but the measurement says it isn't the bottleneck here: stage-1 Recall@50 is already 0.869.

**L7 Principal Defense.** "Ceiling analysis. Swap in an oracle for each stage and measure end-to-end nDCG@10. On SciFact: a perfect stage 2 adds +0.212, perfect stage-1 recall adds +0.043, both together +0.340. The evidence is usually in the candidate set and the ordering loses it, so the re-ranker has 5× the ceiling. I'd fund stage 2 (a fine-tuned cross-encoder or LambdaMART with more features, 04.3), while keeping a stage-1 recall floor in the release gate so retrieval doesn't regress. The ceiling isn't the expected gain: next I'd estimate *achievable* gain from a quick prototype."

**Bar-Raiser Follow-ups.**
- *"Why don't the ceilings add up?"* The stages interact: a perfect re-ranker exploits extra recall that the current one can't.
- *"Same method for an agent?"* Yes: oracle the plan, the tool calls and the retrieval, one at a time.

</details>

<details><summary><b>Q8 · "How many human labels do we need to trust the judge?"</b></summary>

**Initial Prompt.** A budget conversation with the PM.

**L5 Answer.** "100 is plenty."

**Why L5 Fails in Production.** At 70% agreement, 100 labels give about ±9 points, too wide to tell a decent judge from a weak one, and nothing per system or per slice.

**L7 Principal Defense.** "It depends on the precision we need: n ≈ 1.96²·a(1−a)/h². At a ≈ 0.7: 324 for ±5, 900 for ±3, 2,024 for ±2. I'd start with ~400 stratified by system and judge score band, plus a second annotator on 150 of them for the human-human ceiling. Then I'd spend the next labels where they matter most: items where the systems being compared *differ*, because that's where the judge decides the outcome. PPI lets those few hundred human labels correct thousands of judge labels with a valid CI."

**Bar-Raiser Follow-ups.**
- *"Re-validation cadence?"* On any judge model, prompt or rubric change, and when the system's output distribution shifts (a new model). Otherwise a small monthly sample to detect drift.
- *"Who labels?"* Domain experts, using the same rubric text the judge sees, with disagreements adjudicated and the rubric updated (criteria drift).

</details>

<details><summary><b>Q9 · "Our auto-tagger puts 28% of errors in 'other'. Is the analysis useless?"</b></summary>

**Initial Prompt.** The router spreadsheet from §3.1.

**L5 Answer.** "Add more rules until 'other' is empty."

**Why L5 Fails in Production.** Rules encode the causes you already know. The residual is where the *unknown* causes are, and you only find those by reading.

**L7 Principal Defense.** "No, it's exactly as designed. The rules quickly confirmed the known buckets: OOS acceptance 27%, sibling confusion 23%, short queries only 5%. The 28% residual is the reading list. I'd read 40 of them and write new tags from what I see. The example rows already suggest two: keyword collisions ('weather' inside a translation request) and rare vocabulary ('eft'). Then I'd turn the frequent new tags into rules or a small classifier so the next run counts them automatically. The residual share is itself a metric: when it's small, the team understands its failure modes."

**Bar-Raiser Follow-ups.**
- *"Could an LLM do the reading?"* It can propose tags for the residual, which is useful for throughput. A human confirms on a sample before the tags drive priorities.
- *"Multi-tag rows?"* Allow them, count each tag. Shares then sum to more than 100%, and that's fine.

</details>

---

## 7. Invariants Checklist

- [ ] Every project review includes an error-analysis table: ≥ 100 dev errors (or all), tags, counts, and the residual share.
- [ ] Fixes are prioritized by bucket share × fixability ÷ cost, and the bucket's share is quoted as the fix's ceiling.
- [ ] Learning curves (train and dev error vs data size) are produced before requesting more labelled data.
- [ ] Multi-stage pipelines have a ceiling-analysis table (single and joint oracle swaps) before roadmap decisions.
- [ ] A held-out test set is never used during prompt iteration; dev-set size supports the deltas being claimed.
- [ ] Every judged metric links to a versioned `JudgeValidation` record (κ vs human-human κ, Se/Sp, per-system κ, length trend, position-flip rate).
- [ ] Pairwise judging always runs both orders; flips are counted as ties.
- [ ] Absolute judged rates are calibrated (Platt, Rogan–Gladen or PPI) before being reported outside the team.
- [ ] Judge rubrics are binary, criterion-specific, mapped to error-analysis tags, and versioned with the judge model ID.

---

## 8. References

1. A. Ng, *Machine Learning Yearning* (error analysis, bias/variance, learning curves, human-level performance). https://www.deeplearning.ai/resources/
2. A. Ng, *Machine Learning* (Coursera, 2011): "Ceiling analysis: what part of the pipeline to work on next" (photo-OCR pipeline).
3. A. Ng, *Improve Agentic Performance with Evals and Error Analysis, Part 1*, The Batch, 2025-10-15. https://www.deeplearning.ai/the-batch/improve-agentic-performance-with-evals-and-error-analysis-part-1/
4. DeepLearning.AI, *Agentic AI* (A. Ng): evaluation-driven development, component-level evals, error analysis. https://www.deeplearning.ai/courses/agentic-ai
5. J. Cohen, *A Coefficient of Agreement for Nominal Scales*, Educational and Psychological Measurement 20(1), 1960. https://doi.org/10.1177/001316446002000104
6. J. R. Landis, G. Koch, *The Measurement of Observer Agreement for Categorical Data*, Biometrics 33(1), 1977. https://doi.org/10.2307/2529310
7. L. Zheng et al., *Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena*, NeurIPS 2023. https://arxiv.org/abs/2306.05685
8. A. Panickssery, S. Bowman, S. Feng, *LLM Evaluators Recognize and Favor Their Own Generations*, 2024. https://arxiv.org/abs/2404.13076
9. S. Shankar et al., *Who Validates the Validators? Aligning LLM-Assisted Evaluation of LLM Outputs with Human Preferences*, UIST 2024. https://arxiv.org/abs/2404.12272
10. W. Rogan, B. Gladen, *Estimating Prevalence from the Results of a Screening Test*, American Journal of Epidemiology 107(1), 1978. https://doi.org/10.1093/oxfordjournals.aje.a112510
11. A. Angelopoulos, S. Bates, C. Fannjiang, M. Jordan, T. Zrnic, *Prediction-Powered Inference*, Science 382, 2023. https://arxiv.org/abs/2301.09633
12. A. P. Dawid, A. M. Skene, *Maximum Likelihood Estimation of Observer Error-Rates Using the EM Algorithm*, JRSS C 28(1), 1979. https://doi.org/10.2307/2346806
13. H. Husain, *Creating a LLM-as-a-Judge That Drives Business Results*. https://hamel.dev/blog/posts/llm-judge/
14. T. Zhang et al., *RAFT: Adapting Language Model to Domain Specific RAG*, 2024. https://arxiv.org/abs/2403.10131
