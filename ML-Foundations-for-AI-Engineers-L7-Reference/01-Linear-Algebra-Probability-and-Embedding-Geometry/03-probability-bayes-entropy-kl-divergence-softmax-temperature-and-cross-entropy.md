# 01.3 · Probability, Bayes, Entropy, KL Divergence, Softmax Temperature & Cross-Entropy

> **Folder 01 · Linear Algebra, Probability & Embedding Geometry**
> **Measured on:** NumPy 2.5.4, scikit-learn 1.9.1, CPython 3.14.5, Intel i5-11260H (one BLAS thread), Windows 11. Every listing is seeded and deterministic. The simulators (guardrail traffic, overconfident classifiers, a sampling LLM) are labelled as simulators.
> **Design sources:** Guo et al. (temperature scaling, ICML 2017), Hinton, Vinyals & Dean (distillation, 2015), Farquhar et al. (semantic entropy, *Nature* 2024), Thinking Machines "Defeating Nondeterminism in LLM Inference" (2025-09-10), the Hugging Face `transformers` generation source, Anthropic's API-version notes, Rafailov et al. (DPO, 2023). Full list in §8.

---

## 0. Orientation: An LLM Is a Conditional Probability Machine

Andrew Ng's framing for this one: **at every step, a language model outputs a probability distribution over the next token, and everything an AI engineer does is reading, shaping, or checking those distributions.**

- **Sampling** (temperature, top-p, min-p) reshapes the distribution before drawing from it.
- **Training loss** is cross-entropy: the average surprise of the true next token. Perplexity is its exponential.
- **Distillation** makes a small model's distribution match a big one's (KL divergence, with a temperature).
- **RLHF and DPO** maximize reward while a KL penalty keeps the policy near a reference model.
- **Guardrails** are classifiers whose scores become decisions through Bayes' theorem and a cost-weighted threshold.
- **Hallucination detection** reads uncertainty from token log-probabilities, or better, from the spread of *meanings* across samples.
- **LLM-as-a-judge** gives you P(yes), which is only useful once it's calibrated.

### The backend-engineer bridge

| You already know | Probability equivalent | Why it maps |
|---|---|---|
| Alert precision: how many pages were real incidents? | **Bayes with base rates** | A detector with a 1% false-positive rate pages 9,990 times per million benign requests. At 0.1% attack prevalence, 91% of its alerts are false |
| Retries are only independent if failures are | **Correlated errors in cascades** | Two filters with FPRs of 5% and 2% don't give 0.1% if they fail on the same inputs (we measure 0.373%) |
| Compression ratio of a log stream | **Entropy, bits per token** | A model's loss in bits per token *is* its compression rate on that text |
| Diffing two latency histograms | **KL / JS divergence, PSI** | A distance between distributions, which drift detection relies on (Folder 07) |
| Load-shedding thresholds set from cost | **Bayes-optimal decision threshold** | Block when P(bad) > C_FP/(C_FP + C_FN), not at 0.5 |
| Deterministic replay of a request | **Temperature 0 is not determinism** | Floating-point reduction order varies with batch size, so greedy outputs can differ run to run |

### Tier map for this file

| Subtopic | Tier |
|---|---|
| 1.1 Conditional probability and independence | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Bayes' theorem, base rates, odds form, cascades | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Cost-optimal decision thresholds | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Prior (label) shift correction | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Naive Bayes as a baseline | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.6 MLE ⇔ cross-entropy ⇔ KL | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Entropy, bits, perplexity | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Cross-entropy, KL, Gibbs, forward vs reverse KL | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 Jensen–Shannon and the drift metrics preview | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 Mutual information and the InfoNCE bound | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 Softmax: stability, Jacobian, the p − y gradient | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.12 Temperature and sampling filters; temperature 0 ≠ deterministic | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.13 Calibration: temperature scaling, Platt scaling, ECE, LLM-as-judge | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.14 Temperature in distillation (T²) and contrastive losses (τ) | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.15 Sigmoid vs softmax for multi-label guardrails | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.16 Log-probabilities, semantic entropy and hallucination signals | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.17 Label smoothing and focal loss | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.18 KL-regularized RL optimum and DPO | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.19 Measure-theoretic probability, f-divergence theory in general | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 Conditional probability and independence `[MUST-KNOW: Core AI Engineer Edge]`

`P(A | B) = P(A ∩ B) / P(B)`: restrict the world to B, then ask how much of it is A. Independence means `P(A ∩ B) = P(A)P(B)`, i.e. learning B tells you nothing about A. Two rules carry most of production probability:

- **Chain rule:** `P(x₁ … x_T) = Πₜ P(xₜ | x₍<ₜ₎)`. That's literally how an autoregressive LLM scores a sequence. The log of the product is a sum of token log-probs, which is why sequence log-probabilities grow more negative with length, and why comparing raw sequence probabilities across different lengths is a bug (normalize per token).
- **Law of total probability:** `P(A) = Σᵢ P(A | Bᵢ) P(Bᵢ)`. Your system's overall error rate is the traffic-weighted mix of per-segment error rates. That's why a model that is better on every segment can still look worse overall when the traffic mix shifts (Simpson's paradox, Folder 06).

### 1.2 Bayes' theorem, base rates, the odds form, and cascades `[MUST-KNOW: Core AI Engineer Edge]`

```text
P(attack | flagged) = P(flagged | attack) P(attack) / P(flagged)
                    = TPR·π / (TPR·π + FPR·(1 − π))          π = prevalence (the base rate)
```

**The guardrail table every AI engineer should know by heart.** A jailbreak detector with TPR 0.99 and FPR 0.01 ("99% accurate"), per 1M requests (§3.1):

```text
prevalence precision true alerts false alerts
  10.0000%     0.917      99,000        9,000
   1.0000%     0.500       9,900        9,900
   0.1000%     0.090         990        9,990
   0.0100%     0.010          99        9,999
```

At a realistic 0.1% attack rate, **91% of its blocks hit legitimate users**. The detector didn't get worse. The base rate dominates.

**The odds form** is the version you can do in your head:

```text
posterior odds = prior odds × likelihood ratio          LR⁺ = TPR / FPR
0.001/0.999 × (0.99/0.01) = 0.001001 × 99 = 0.0991   →   P = 0.0991/1.0991 = 0.0902   ✓
```

Evidence *multiplies* odds, and independent pieces of evidence multiply in turn. That's the principled way to combine signals: add log-likelihood ratios, which is exactly what logistic regression does (Folder 02).

**Cascades and the independence assumption.** The standard fix for base rates is to chain a cheap high-recall stage (a small classifier: TPR 0.995, FPR 0.05) with an expensive precise stage (an LLM judge: TPR 0.95, FPR 0.02), and block only when both fire. If their errors were independent, the combined FPR would be 0.05 × 0.02 = 0.001. Our simulation gives both stages the same marginal rates, and in the second run their errors share a "hard input" factor (pentest documentation, fiction, security research):

```text
independent errors                         FPR 0.00099 (naive product 0.00100)  TPR 0.947  precision @1% prevalence 0.907
correlated errors (shared 'hard' latent)   FPR 0.00373 (naive product 0.00100)  TPR 0.946  precision @1% prevalence 0.719
```

**With correlated errors, the false-positive rate is 3.7× the product estimate, and precision falls from 0.907 to 0.719.** Real guardrail stages are correlated: they were trained on similar data, and they fail on the same hard benign inputs. *Measure the joint FPR on held-out benign traffic.* Never multiply marginals.

### 1.3 The cost-optimal decision threshold `[MUST-KNOW: Core AI Engineer Edge]`

Given a **calibrated** score s = P(bad | x), blocking costs C_FP if the input is benign, and allowing costs C_FN if it is bad. Block when the expected cost of blocking is lower:

```text
cost(block) = (1 − s)·C_FP        cost(allow) = s·C_FN
block  ⇔  (1 − s)·C_FP < s·C_FN  ⇔  s > C_FP / (C_FP + C_FN) = t*          ∎
```

With C_FP = 1 (an annoyed user) and C_FN = 50 (a successful jailbreak), t* = 1/51 = **0.0196**, not 0.5. §3.1 confirms by brute force on 400k calibrated scores: the empirical optimum is 0.0229, close to t* (the grid and sampling noise account for the gap). The expected cost there is **0.521**, vs **2.340** at the default 0.5 threshold, a 4.5× difference from one constant.

Two preconditions are easy to miss. First, the formula needs *calibrated* probabilities (§1.13). Second, it needs costs that someone actually owns. Write them down in the design doc, because the threshold is a business decision expressed as a number.

### 1.4 Prior shift correction (label shift) `[MUST-KNOW: Core AI Engineer Edge]`

Guardrail classifiers are often trained on **balanced** data (50/50 attacks and benign) and deployed where attacks are 1%. If the class-conditional distributions p(x | y) are unchanged and only the prior moved, Bayes' rule gives an exact correction:

```text
p_deploy(y=1 | x) = p_train(1|x)·(π/π_t) / [ p_train(1|x)·(π/π_t) + (1 − p_train(1|x))·((1−π)/(1−π_t)) ]
```

*Derivation:* p(y | x) ∝ p(x | y)·p(y). The likelihood is shared, so re-weight each class's posterior by the ratio of new to old prior and renormalize. ∎ §3.1, trained at 50/50 and deployed at 1%:

```text
raw (training prior)   log-loss 0.3548  mean p 0.2298 (true rate 0.0101)  flags 0.1651  precision@0.5 0.052
prior-corrected        log-loss 0.0371  mean p 0.0100 (true rate 0.0101)  flags 0.0015  precision@0.5 0.677
```

Uncorrected, the classifier says "23% of traffic looks like attacks" and flags 16.5% of all requests at 5% precision. One formula brings the mean probability to the true rate, cuts log-loss 9.6×, and raises precision to 0.677. The same correction applies to LLM-as-judge setups calibrated on a balanced labelled set.

### 1.5 Naive Bayes as a baseline `[GOOD-TO-KNOW: Architectural Literacy]`

Naive Bayes assumes features are conditionally independent given the class: `log P(y | x) = log P(y) + Σⱼ log P(xⱼ | y) + const`. That's a sum of per-token log-likelihood ratios, i.e. a linear model in log space. On bag-of-words text it is a fast, surprisingly strong baseline for spam, toxicity and topic triage, with essentially zero inference cost. Its probabilities are badly overconfident, because correlated tokens get counted as independent evidence (the cascade problem again), so calibrate it before thresholding. Folder 02 shows when logistic regression on embeddings beats it.

### 1.6 MLE ⇔ minimizing cross-entropy ⇔ minimizing KL `[MUST-KNOW: Core AI Engineer Edge]`

Given data x₁ … x_N from an unknown distribution p, maximum likelihood picks the model q_θ that maximizes `Πᵢ q_θ(xᵢ)`. Take logs and divide by N:

```text
argmax_θ (1/N) Σᵢ log q_θ(xᵢ)
  = argmin_θ  − E_{x∼p̂} [log q_θ(x)]           p̂ = the empirical distribution of the data
  = argmin_θ  H(p̂, q_θ)                         (cross-entropy)
  = argmin_θ  H(p̂) + KL(p̂ ‖ q_θ)               (§1.8 identity; H(p̂) doesn't depend on θ)
  = argmin_θ  KL(p̂ ‖ q_θ)                                                         ∎
```

So **"train with cross-entropy loss", "maximize likelihood" and "minimize forward KL to the data" are the same objective.** That's why LLM pre-training loss is reported in nats or bits per token: it is a cross-entropy. §3.3 trains a 20-token unigram "language model" by gradient descent on cross-entropy and recovers the empirical frequencies (max error 1.45e-05). At the optimum, the training CE equals the entropy of the data (2.3289 nats).

### 1.7 Entropy, bits, and perplexity `[MUST-KNOW: Core AI Engineer Edge]`

`H(p) = −Σ p(x) log p(x)` is the expected surprise `−log p(x)`. In bits (log₂), it's the minimum average code length for samples of p (Shannon's source coding theorem). In nats (ln), it's what frameworks compute. Convert with `bits = nats / ln 2`.

- Uniform over K outcomes is the maximum: H = log K. A uniform distribution over a 128,000-token vocabulary has H = 16.966 bits.
- A one-hot distribution has H = 0.
- **Perplexity** = exp(cross-entropy in nats) = the effective number of equally likely choices per token.

| LM loss (nats/token) | bits/token | perplexity |
|---:|---:|---:|
| 1.5 | 2.164 | 4.48 |
| 2.0 | 2.885 | 7.39 |
| 2.5 | 3.607 | 12.18 |

Production readings:

- A loss of 2.0 means the model is, on average, as uncertain as a fair choice among 7.4 tokens.
- **Perplexity comparisons are only valid with the same tokenizer and text.** A model with a bigger vocabulary predicts longer tokens, so its per-token perplexity isn't comparable. Use bits per byte or per character across tokenizers.
- Token entropy at each generation step is a cheap uncertainty signal (§1.16).

### 1.8 Cross-entropy, KL divergence, Gibbs' inequality, and forward vs reverse KL `[MUST-KNOW: Core AI Engineer Edge]`

```text
H(p, q)   = −Σ p log q                           (cross-entropy: code built for q, data from p)
KL(p ‖ q) =  Σ p log(p/q) = H(p, q) − H(p)       (the extra bits paid for using the wrong code)
```

**Gibbs' inequality: KL(p ‖ q) ≥ 0, with equality iff p = q.** *Proof via Jensen:* −log is strictly convex, so

```text
KL(p‖q) = E_p[−log(q/p)] ≥ −log E_p[q/p] = −log Σ_{x: p>0} q(x) ≥ −log 1 = 0
```

with equality only if q/p is constant on p's support, i.e. q = p. ∎ §3.3 checks the identity H(p,q) = H(p) + KL(p‖q) on 20,000 random pairs (max error 3.55e-15) and finds min KL ≥ 0.

**KL is asymmetric, and the asymmetry is a design choice.**

- `KL(p ‖ q)` (forward) averages over p. It is **infinite if q puts ~0 where p has mass**. In §3.3, q placing 1e-8 on outcomes where p places 0.5 sends KL(p‖q) to 8.8 and rising, while KL(q‖p) stays at 0.693. Forward KL forces q to *cover* everything p does: it is **mode-covering** (zero-avoiding).
- `KL(q ‖ p)` (reverse) averages over q. q is penalized for putting mass where p has none, but not for ignoring regions of p. It is **mode-seeking** (zero-forcing).

Fit one Gaussian q to a bimodal p (modes at ±3) and the two divergences disagree (§3.3):

```text
forward KL(p||q)  best mu = +0.00, sigma = 3.10  (divergence 0.789)
reverse KL(q||p)  best mu = +3.00, sigma = 0.70  (divergence 0.693)
```

```text
   p:      ▁▃█▃▁               ▁▃█▃▁          (two modes, at −3 and +3)
 forward:  ▁▁▂▂▃▃▄▄▅▅▅▅▅▄▄▃▃▂▂▁▁             q spreads over both modes and the gap between
 reverse:                       ▁▃█▃▁         q locks onto one mode and ignores the other
```

**Where each one shows up in AI engineering:**

| Objective | Divergence | Behaviour you get |
|---|---|---|
| Pre-training / SFT (cross-entropy on data) | forward KL(data ‖ model) | Covers the data, including its noise, so it hedges |
| Classic distillation (Hinton et al.) | forward KL(teacher ‖ student) on softened distributions | The student imitates the teacher's whole distribution, including "dark knowledge" in the low-probability tokens |
| On-policy distillation (student samples, teacher scores each token) | per-token reverse KL(student ‖ teacher) | Mode-seeking: the student commits to what the teacher would say on the student's own trajectories |
| RLHF / RLVR KL penalty | KL(policy ‖ reference) | Keeps the tuned policy from drifting into reward hacks (§1.18) |
| Drift detection | Symmetric versions (JS, PSI) | No infinities when bins are empty (§1.9) |

### 1.9 Jensen–Shannon divergence and the drift-metrics preview `[GOOD-TO-KNOW: Architectural Literacy]`

`JS(p, q) = ½ KL(p ‖ m) + ½ KL(q ‖ m)` with `m = ½(p + q)`. It is symmetric, always finite, and bounded by ln 2 (reached for disjoint supports: §3.3 measures 0.693147 = ln 2, where KL would be infinite). √JS is a true metric. The **Population Stability Index** used in credit-risk and ML monitoring is `Σ (pᵢ − qᵢ) ln(pᵢ/qᵢ)` = KL(p‖q) + KL(q‖p), the symmetrized (Jeffreys) divergence over bins. Folder 07 applies these to embedding drift and explains the binning choices that make PSI noisy.

### 1.10 Mutual information and the InfoNCE bound `[GOOD-TO-KNOW: Architectural Literacy]`

`I(X; Y) = KL(p(x, y) ‖ p(x)p(y))`: how far the joint distribution is from independence, i.e. how many bits knowing Y saves you about X. Contrastive training of embedding models maximizes a lower bound on it: with one positive and N − 1 negatives per batch, Oord et al. (CPC, 2018) show `I(X; Y) ≥ log N − L_InfoNCE`. Two consequences preview Folder 04. Bigger batches (larger N) allow a tighter bound, which is one reason embedding models train with huge batches. And the loss has a temperature τ (§1.14) that controls how hard the negatives push.

### 1.11 Softmax: stability, the Jacobian, and the p − y gradient `[MUST-KNOW: Core AI Engineer Edge]`

```text
softmax(z)ᵢ = exp(zᵢ) / Σⱼ exp(zⱼ)
```

**Shift invariance and the log-sum-exp trick.** `softmax(z + c) = softmax(z)` for any constant c, because exp(c) cancels between numerator and denominator. So compute it as `exp(zᵢ − max z) / Σ exp(zⱼ − max z)`, where every exponent is ≤ 0 and nothing overflows. §3.2: the naive formula on logits [1000, 999, 998] returns `[nan nan nan]`, and the stable one returns [0.665241, 0.244728, 0.090031]. In float16, exp overflows above z = 11.09, which is why attention kernels keep the running max in fp32 (FlashAttention's online softmax is this trick, applied block by block).

**The Jacobian.** `∂pᵢ/∂zⱼ = pᵢ(δᵢⱼ − pⱼ)`, i.e. `J = diag(p) − ppᵀ`. It is symmetric and positive semi-definite. For a unit vector v, `vᵀJv = Var_p(v)`, which Popoviciu's inequality bounds by ¼(max v − min v)² ≤ ½. J is also the Hessian of the cross-entropy with respect to the logits, so gradient descent on logits is stable for any step size below 2/λ_max ≥ 4. The unigram LM in §3.3 uses 3.0.

**The cross-entropy gradient: the single most used derivative in deep learning.** For a one-hot target y (true class k):

```text
L = −log p_k = −z_k + log Σⱼ exp(zⱼ)
∂L/∂zⱼ = −δⱼₖ + exp(zⱼ)/Σ exp = pⱼ − yⱼ          ⇒   ∇_z L = p − y          ∎
```

The gradient is the prediction error, bounded in [−1, 1] per coordinate, so it never explodes from the loss itself. §3.2 checks it against finite differences to 1.4e-10. Every classifier head in Folder 02 and every LM training step uses it.

### 1.12 Temperature and sampling filters, and why temperature 0 is not determinism `[MUST-KNOW: Core AI Engineer Edge]`

```text
p_i(T) = exp(z_i / T) / Σⱼ exp(z_j / T)
T → 0:  all mass on argmax (greedy)        T = 1: the model's distribution        T → ∞: uniform
```

**Entropy rises monotonically with T, and its derivative has a closed form.** Write β = 1/T. Then `H(β) = log Z(β) − β E_p[z]`, and differentiating gives `dH/dβ = −β Var_p(z)`. By the chain rule (dβ/dT = −1/T²):

```text
dH/dT = Var_p(z) / T³ ≥ 0                                                          ∎
```

§3.2 checks it against finite differences at T = 0.5, 1, 2: 4.922083, 11.291222 and 0.629468 nats, matching to six digits.

**What temperature does on a realistic vocabulary.** A Zipf-like distribution over 50k tokens (§3.2):

```text
    T  H bits perplexity  p(top1) top-p .9 keeps min-p .05 keeps
  0.1   0.590        1.5   0.8726              2               2
  0.7   4.708       26.1   0.2462             46              13
  1.0   9.602      777.1   0.0864          7,664              19
  1.5  14.089    17427.0   0.0111         33,510              97
```

- **Top-p (nucleus, Holtzman et al.)** keeps the smallest set of tokens with cumulative probability ≥ p. Its size explodes with T: from 46 tokens at T = 0.7 to 33,510 at T = 1.5. At high T, top-p 0.9 admits a long tail of junk.
- **Min-p** keeps tokens with p ≥ min_p × p_max. It scales with the model's confidence, keeping 19 tokens at T = 1.0 and 97 at T = 1.5. That's why min-p holds coherence better at high temperatures than top-p does.

**Order of operations matters.** In Hugging Face `transformers` (main-branch `_get_logits_processor`), the sampling warpers are appended as **temperature → top-k → top-p → min-p**. A source comment notes that min-p is "applied after temperature scaling". Applying top-p *before* temperature selects a different set: at T = 1.5 and top_p = 0.9, temperature-first keeps 33,510 tokens, top-p-first keeps 7,664 (§3.2). When you port sampling settings between stacks (HF, vLLM, llama.cpp, a vendor API), **check the order**, or "the same settings" produce different text.

**Temperature 0 is not determinism.** Floating-point addition is not associative. In float32, `(1e8 + −1e8) + 1 = 1` but `1e8 + (−1e8 + 1) = 0` (§3.2). GPU kernels change their reduction order with batch size and tiling, so the same logits computed in a different batch differ in the last bits. §3.2 measures a 3.3e-6 spread across three reduction orders of one 4096-dim projection. Greedy decoding flips whenever a top-2 gap is smaller than that noise, and once one token differs the continuations diverge. Thinking Machines' measurement (Horace He et al., 2025-09-10): **1,000 temperature-0 completions of one prompt on Qwen3-235B-A22B gave 80 unique outputs**, identical for 102 tokens before splitting at token 103. The cause is a lack of **batch invariance** in RMSNorm, matmul and attention kernels. With batch-invariant kernels, all 1,000 were identical, at a cost: 26 s for default vLLM vs 55 s unoptimized deterministic and 42 s with an improved attention kernel, on Qwen-3-8B.

**And frontier APIs are removing the knob.** Anthropic's API version `2026-10-21` returns a 400 error for any Messages request that sends `temperature`, `top_p` or `top_k`, on every model. Claude 4.7 and later models already accept only the default sampling values. So "set temperature to 0 for consistency" is not even available on current Claude models. Consistency comes from structured outputs, validators, self-consistency voting and caching, not from a sampling knob. The temperature math in this section still matters for (a) open-weight models you serve yourself, (b) the calibration temperature in §1.13, which is a post-hoc transform on *your* classifier, and (c) the training temperatures in §1.14.

### 1.13 Calibration: temperature scaling, Platt scaling, ECE, and LLM-as-judge `[MUST-KNOW: Core AI Engineer Edge]`

A model is **calibrated** when, among all predictions made with confidence 0.8, about 80% are correct. Thresholds (§1.3), cascades and abstention all assume it. Guo et al. (ICML 2017) showed modern deep networks are typically **overconfident**, and that one parameter fixes most of it:

```text
temperature scaling:  p = softmax(z / T),  T fitted by minimizing NLL on a held-out set
```

Dividing all logits by T > 0 preserves their order, so **accuracy cannot change**. Only the confidence changes. §3.4, on an overconfident 10-class classifier:

```text
== 1. fitted temperature T = 2.012 (on 15,000 validation examples) ==
uncalibrated        accuracy 0.7563  NLL 1.2838  ECE 0.1823  mean confidence 0.9386
temperature-scaled  accuracy 0.7563  NLL 0.9210  ECE 0.0088  mean confidence 0.7504
```

**Expected calibration error (ECE)** bins predictions by confidence and averages |confidence − accuracy| weighted by bin size. Here ECE drops 21× (0.1823 → 0.0088). Before scaling, the 6,655 predictions made with confidence > 0.99 were right only 89.7% of the time.

**Why calibration is a cascade enabler.** After calibration, "answer locally when confidence ≥ t, else escalate" behaves predictably. The accuracy on the answered slice matches the mean confidence there:

```text
    t  coverage  accuracy on answered  expected (mean conf)
 0.50     0.895                 0.795                 0.791
 0.70     0.674                 0.853                 0.850
 0.90     0.213                 0.939                 0.938
```

You can now pick t for a target local accuracy and know the escalation rate in advance. That's the quantitative core of the model cascade (Folder 07).

**LLM-as-a-judge needs Platt, not just temperature.** Read the judge's P(yes) from token log-probabilities (where available, §1.16). A judge that is both overconfident *and* biased toward "yes" has an intercept error, and temperature scaling (slope only) can't fix an intercept. Platt scaling fits `σ(a·z + b)`, a one-feature logistic regression on held-out human labels:

```text
raw judge                mean P(yes) 0.561 (human yes-rate 0.387)  NLL 0.6516  ECE 0.1024
temperature T=2.44       mean P(yes) 0.560 (human yes-rate 0.387)  NLL 0.5482  ECE 0.0335
Platt a=0.54 b=-1.12     mean P(yes) 0.384 (human yes-rate 0.387)  NLL 0.4581  ECE 0.0109
```

Temperature leaves the judge saying "yes" 56% of the time when humans say 39%. Platt corrects the base rate. Folder 06 builds the full judge-calibration workflow: agreement with humans, confusion matrices, and bias audits.

### 1.14 Temperature in distillation (T²) and in contrastive losses (τ) `[GOOD-TO-KNOW: Architectural Literacy]`

**Distillation** (Hinton, Vinyals & Dean, 2015) trains the student on the teacher's *softened* distribution, `p_t(T) = softmax(z_t/T)`, so that the relative probabilities of wrong answers ("dark knowledge") carry signal. The gradient of the soft-target cross-entropy with respect to the student logits is

```text
∂/∂z_s  H(p_t(T), p_s(T)) = (p_s(T) − p_t(T)) / T
```

For large T, both distributions approach uniform and `p_s − p_t ≈ (z_s − z_t)/(K·T)`, so the gradient scales as **1/T²**. Multiplying the soft loss by T² keeps its contribution comparable to the hard-label loss as you change T. §3.2: ‖grad‖·T² goes 0.4917, 0.4934, 0.4339, 0.3933, 0.3757 for T = 1, 2, 4, 8, 16. It flattens toward a constant, the 1/T² regime.

**Contrastive losses** (InfoNCE, used to train embedding models, Folder 04) divide similarities by a temperature τ before the softmax over in-batch candidates. Small τ (e.g. 0.05 in SimCSE; CLIP learns it, starting at 0.07) sharpens the distribution, which concentrates the gradient on the hardest negatives. Too small, and training is dominated by a few (possibly mislabelled) negatives. It is the same knob as sampling temperature, used to shape gradients instead of text.

### 1.15 Sigmoid vs softmax for multi-label guardrails `[MUST-KNOW: Core AI Engineer Edge]`

Softmax makes classes *compete*: probabilities sum to 1. That is correct for "exactly one of K" (routing to one intent). It is wrong for guardrails, where a prompt can be PII-leaking *and* toxic *and* a jailbreak at once. With one head emitting logits [pii 2.1, toxic 2.1, jailbreak −3.0, benign −1.0] (§3.2):

```text
softmax:  pii=0.49  toxic=0.49  jailbreak=0.00  benign=0.02   -> at threshold 0.5 flags: []
sigmoids: pii=0.89  toxic=0.89  jailbreak=0.05  benign=0.27   -> at threshold 0.5 flags: ['pii', 'toxic']
```

**Softmax lets a doubly violating prompt through**, because the two violations split the probability mass. Multi-label means one sigmoid per label, each trained with binary cross-entropy, each with its own calibrated threshold from §1.3 (the cost of a missed PII leak is not the cost of a missed toxic reply).

### 1.16 Log-probabilities, semantic entropy, and hallucination signals `[MUST-KNOW: Core AI Engineer Edge]`

**Token-level signals** (cheap, one generation):

- Mean token log-prob, or the length-normalized sequence probability.
- Minimum token log-prob, to spot the one guessed entity.
- Per-step entropy of the next-token distribution.

These flag low-confidence spans, but they confuse *lexical* uncertainty ("Paris" vs "The capital is Paris") with *semantic* uncertainty (Paris vs Lyon).

**Semantic entropy** (Farquhar, Kossen, Kuhn & Gal, *Nature*, 2024-06-19):

1. Sample N answers.
2. Cluster them by **bidirectional entailment**: A and B are in the same cluster if each entails the other, judged by an NLI model or an LLM.
3. Compute entropy over the *meaning clusters*.

High semantic entropy flags **confabulations**, the arbitrary and incorrect generations. It doesn't catch *systematic* errors, where the model is consistently wrong. The authors found 10 samples a good cost/benefit point. §3.5 runs the pipeline against a seeded answer simulator:

```text
signal                              AUROC (detect wrong)  mean | right  mean | wrong
naive entropy over exact strings                   0.843         1.774         2.087
semantic entropy over meanings                     0.896         0.592         1.346
semantic entropy, over-merged                      0.883         0.565         1.194
```

Naive entropy is inflated by paraphrases on questions the model knows (1.774 even when right). Clustering by meaning separates right from wrong much better. An over-eager equivalence check (merging "1912" with "April 1912", the failure the authors themselves describe) hides some of the uncertainty. As an abstention signal: answering only when semantic entropy ≤ 0.9 drops the error rate on answered questions from 28.3% to **0.6%**, while answering 55.2% of them. The cost is 10 generations plus ~15 entailment checks per question (greedy clustering; 45 for all pairs), so use it on high-stakes or flagged traffic, not everywhere.

**Availability check before you design on log-probs** (as of 2026-10):

- The Claude Messages API does not return token log-probabilities (⚠ verify against current docs), and API version `2026-10-21` removes the sampling knobs entirely (§1.12).
- OpenAI exposes `logprobs` / `top_logprobs` for some models. Community reports say reasoning models reject logprobs, or return them inconsistently with structured outputs (⚠ secondhand: verify per model).
- Self-hosted open-weight models (vLLM, TGI) give you full log-probs.

So: **design hallucination detection around sampling plus semantic clustering, or around a trained probe/classifier on your own model, and treat vendor log-probs as an optional extra signal.**

### 1.17 Label smoothing and focal loss `[GOOD-TO-KNOW: Architectural Literacy]`

- **Label smoothing** trains against `y_smooth = (1 − ε)·onehot + ε/K`. It caps how confident the model can get (the optimal logit gap becomes finite), which often improves calibration and generalization. Müller et al. (2019) found it can *hurt* distillation, because it erases the relative information between wrong classes that the student would learn from.
- **Focal loss** (Lin et al., 2017) multiplies cross-entropy by (1 − p_true)^γ, down-weighting easy examples so training focuses on hard ones. Use it for extreme imbalance, like guardrails at 0.1% prevalence. Its probabilities are no longer calibrated, so apply §1.13 before thresholding.

### 1.18 The KL-regularized RL optimum and DPO `[GOOD-TO-KNOW: Architectural Literacy]`

RLHF-style fine-tuning maximizes `E_{y∼π}[r(y)] − β·KL(π ‖ π_ref)`. Over a discrete set of responses, this has a closed-form maximizer (a Gibbs distribution):

```text
π*(y) = π_ref(y)·exp(r(y)/β) / Z
```

*Derivation:* add a Lagrange multiplier for Σπ = 1, set the derivative to zero: `r(y) − β(log π(y)/π_ref(y) + 1) − λ = 0`, which gives log π = log π_ref + r/β + const. ∎ §3.3 checks it against gradient ascent on five candidate responses:

```text
  beta     closed form pi* ~ pi_ref*exp(r/beta)                  gradient ascent   E[r]     KL
   0.1                         [0. 0. 0. 0. 1.]  [0.    0.    0.    0.001 0.999]  2.998  2.985
   1.0          [0.131 0.162 0.134 0.243 0.33 ]  [0.131 0.162 0.134 0.243 0.33 ]  1.690  0.576
   5.0          [0.346 0.287 0.159 0.129 0.079]  [0.346 0.287 0.159 0.129 0.079]  0.797  0.015
```

β is the leash. As β → 0, all mass goes to the highest-reward response: if the reward model has a bug, the policy finds it (**reward hacking**). As β → ∞, the policy stays at the reference. **DPO** (Rafailov et al., 2023) rearranges the same optimum, `r(y) = β log(π*(y)/π_ref(y)) + β log Z`, into a loss on preference pairs where Z cancels. That lets you train the policy directly on preferences, with no separate reward model or RL loop.

### 1.19 Measure-theoretic probability and general f-divergences `[SKIP: Academic/Research Only]`

Densities on continuous spaces, Radon–Nikodym derivatives, and the general f-divergence family (KL, reverse KL, χ², Hellinger and total variation all being special cases) unify everything above, but no production decision depends on them. If a paper's loss is "an f-divergence", map it back to forward vs reverse behaviour (§1.8) and move on.

---

## 2. Where It Beats an LLM in Production

### 2.1 Calibrated probabilities are a feature LLM answers don't have

A small classifier (logistic regression or LightGBM on frozen embeddings, Folder 02) gives you a *number* you can calibrate (§1.13), prior-correct (§1.4) and threshold by cost (§1.3). Ask an LLM "is this a jailbreak, and how confident are you?" and you get text. Verbalized confidence from LLMs tends to be overconfident: Xiong et al. (2023) evaluated confidence elicitation across models and found that verbalized scores cluster at high values. So the decision layer of a guardrail should be a calibrated score, even when an LLM produces part of the evidence.

| Need | Calibrated small model | LLM in the loop |
|---|---|---|
| Block at the cost-optimal threshold t* = C_FP/(C_FP + C_FN) | Directly (§1.3: expected cost 0.521 at t* vs 2.340 at 0.5) | Only if you calibrate its P(yes), which needs log-probs (§1.16) or sampling |
| Re-target a new deployment prevalence | Closed-form prior correction (§1.4: log-loss 0.355 → 0.037) | Re-prompting doesn't fix base-rate miscalibration |
| Predictable escalation rate | Calibrated confidence ≥ t answers 67.4% of traffic at 0.853 accuracy (t = 0.7, §3.4) | Unknown until measured, and it moves with prompt changes |
| Per-request cost | One embedding (shared with routing/caching) + microseconds | A full LLM call (01.1 §2: 113× to 4,533× an embedding call) |

### 2.2 The production patterns

1. **Staged guardrails with measured joint error rates.** A cheap, high-recall classifier screens everything. An LLM judge sees only what it flags, and its P(yes) is Platt-calibrated on human labels. The block decision applies the cost-optimal threshold to the *calibrated* combined score. The joint FPR is measured on held-out benign traffic, never multiplied from marginals (§1.2: 0.373% measured vs 0.100% assumed).
2. **Confidence-gated cascades.** The cheap model answers when its calibrated confidence ≥ t. Pick t from the selective-prediction table for a target accuracy, and the escalation rate follows. Folder 07 turns this into the full regex → BERT → GBDT → LLM cascade.
3. **Selective answering for factual QA.** When a wrong answer is expensive, sample ~10 answers on flagged traffic and abstain or escalate when semantic entropy is high. §3.5: error rate on answered questions goes from 28.3% to 0.6% at 55% coverage, for ~10× generation cost on that slice.
4. **Multi-label policy enforcement with independent sigmoids**, each with its own cost-derived threshold (§1.15).

### 2.3 When the LLM is the right tool

- Novel attack patterns with no labelled examples yet. The LLM judge is the zero-shot fallback, and its decisions (audited) become training labels.
- Policies that need reasoning over long context ("does this message, given the prior 20 turns, attempt social engineering?").
- Explanations for human reviewers. The classifier decides, the LLM explains.

---

## 3. Production Code Blueprint

### 3.1 Bayes for guardrails: base rates, odds, cascades, cost thresholds, prior shift

```python
"""bayes_guardrail_base_rates.py - Bayes' theorem as a guardrail-design tool: base rates, cascades, thresholds, prior shift.

  1. A "99% accurate" jailbreak detector at 0.1% prevalence is wrong 9 times out of 10 when it fires.
  2. Odds form: posterior odds = prior odds x likelihood ratio.
  3. Two-stage cascade: the product-of-FPRs estimate holds only if the stages' errors are independent.
  4. With calibrated scores, the cost-optimal block threshold is C_FP / (C_FP + C_FN) - checked by brute force.
  5. A classifier trained on balanced data must be prior-corrected before you threshold it in production.
"""
import numpy as np

rng = np.random.default_rng(13)

print("== 1. precision of a TPR=0.99 / FPR=0.01 detector vs prevalence (per 1M requests) ==")
TPR, FPR = 0.99, 0.01
print(f"{'prevalence':>10} {'precision':>9} {'true alerts':>11} {'false alerts':>12}")
for prev in (0.10, 0.01, 0.001, 0.0001):
    prec = TPR * prev / (TPR * prev + FPR * (1 - prev))
    print(f"{prev:>10.4%} {prec:>9.3f} {TPR * prev * 1e6:>11,.0f} {FPR * (1 - prev) * 1e6:>12,.0f}")
prec_001 = TPR * 0.001 / (TPR * 0.001 + FPR * 0.999)
assert prec_001 < 0.1

print("\n== 2. odds form ==")
prior = 0.001
post_odds = prior / (1 - prior) * (TPR / FPR)
print(f"prior odds {prior / (1 - prior):.5f} x LR+ {TPR / FPR:.0f} = posterior odds {post_odds:.5f} "
      f"-> P = {post_odds / (1 + post_odds):.4f} (matches {prec_001:.4f})")
assert abs(post_odds / (1 + post_odds) - prec_001) < 1e-12

print("\n== 3. cascade: stage 1 (fast classifier, TPR .995 / FPR .05) -> stage 2 (LLM judge, TPR .95 / FPR .02) ==")
n_benign, n_attack = 2_000_000, 20_000


def stage_flags(hard, rate, noise):
    """Flag when hardness + private noise crosses the quantile that gives the target marginal flag rate."""
    s = hard + noise * rng.standard_normal(len(hard))
    return s > np.quantile(s, 1 - rate)


for corr_name, noise in (("independent errors", None), ("correlated errors (shared 'hard' latent)", 0.25)):
    if noise is None:
        b1 = rng.random(n_benign) < 0.05
        b2 = rng.random(n_benign) < 0.02
        a1 = rng.random(n_attack) < 0.995
        a2 = rng.random(n_attack) < 0.95
    else:
        hb = rng.random(n_benign)                     # how attack-like each benign prompt looks (pentest docs, fiction...)
        ha = rng.random(n_attack)                     # how blatant each attack is
        b1, b2 = stage_flags(hb, 0.05, noise), stage_flags(hb, 0.02, noise)
        a1, a2 = stage_flags(ha, 0.995, noise), stage_flags(ha, 0.95, noise)
    fpr, tpr = np.mean(b1 & b2), np.mean(a1 & a2)
    prec = tpr * 0.01 / (tpr * 0.01 + fpr * 0.99)
    print(f"{corr_name:42s} FPR {fpr:.5f} (naive product 0.00100)  TPR {tpr:.3f}  precision @1% prevalence {prec:.3f}")
    if noise is not None:
        assert fpr > 3 * 0.001

print("\n== 4. cost-optimal threshold on calibrated scores (C_FP = 1, C_FN = 50) ==")
C_FP, C_FN = 1.0, 50.0
s = rng.beta(0.3, 6.0, 400_000)                      # calibrated P(attack | x)
y = rng.random(len(s)) < s                           # labels drawn from the scores => perfectly calibrated
grid = np.linspace(0.001, 0.2, 400)
cost = [(C_FP * np.sum((s > t) & ~y) + C_FN * np.sum((s <= t) & y)) / len(s) for t in grid]
t_star = C_FP / (C_FP + C_FN)
print(f"analytic t* = C_FP/(C_FP+C_FN) = {t_star:.4f}; brute-force argmin = {grid[int(np.argmin(cost))]:.4f}; "
      f"cost at t* {np.interp(t_star, grid, cost):.4f} vs at t=0.5 {(C_FP * np.sum((s > .5) & ~y) + C_FN * np.sum((s <= .5) & y)) / len(s):.4f}")
assert abs(grid[int(np.argmin(cost))] - t_star) < 0.01

print("\n== 5. prior shift: trained at 50/50, deployed at 1% attacks ==")
pi_t, pi = 0.5, 0.01
n = 500_000
yd = rng.random(n) < pi
x = np.where(yd, 1.0, -1.0) + rng.standard_normal(n)        # class-conditionals N(+1,1) vs N(-1,1)
p_train = 1 / (1 + np.exp(-2 * x))                          # Bayes posterior under the 50/50 training prior
w1, w0 = pi / pi_t, (1 - pi) / (1 - pi_t)
p_corr = p_train * w1 / (p_train * w1 + (1 - p_train) * w0)


def report(p, name):
    ll = -np.mean(np.where(yd, np.log(p), np.log(1 - p)))
    flag = p > 0.5
    prec = np.sum(flag & yd) / max(flag.sum(), 1)
    print(f"{name:22s} log-loss {ll:.4f}  mean p {p.mean():.4f} (true rate {yd.mean():.4f})  "
          f"flags {flag.mean():.4f}  precision@0.5 {prec:.3f}")
    return ll


ll_raw = report(p_train, "raw (training prior)")
ll_cor = report(p_corr, "prior-corrected")
assert ll_cor < ll_raw
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. precision of a TPR=0.99 / FPR=0.01 detector vs prevalence (per 1M requests) ==
prevalence precision true alerts false alerts
  10.0000%     0.917      99,000        9,000
   1.0000%     0.500       9,900        9,900
   0.1000%     0.090         990        9,990
   0.0100%     0.010          99        9,999

== 2. odds form ==
prior odds 0.00100 x LR+ 99 = posterior odds 0.09910 -> P = 0.0902 (matches 0.0902)

== 3. cascade: stage 1 (fast classifier, TPR .995 / FPR .05) -> stage 2 (LLM judge, TPR .95 / FPR .02) ==
independent errors                         FPR 0.00099 (naive product 0.00100)  TPR 0.947  precision @1% prevalence 0.907
correlated errors (shared 'hard' latent)   FPR 0.00373 (naive product 0.00100)  TPR 0.946  precision @1% prevalence 0.719

== 4. cost-optimal threshold on calibrated scores (C_FP = 1, C_FN = 50) ==
analytic t* = C_FP/(C_FP+C_FN) = 0.0196; brute-force argmin = 0.0229; cost at t* 0.5208 vs at t=0.5 2.3396

== 5. prior shift: trained at 50/50, deployed at 1% attacks ==
raw (training prior)   log-loss 0.3548  mean p 0.2298 (true rate 0.0101)  flags 0.1651  precision@0.5 0.052
prior-corrected        log-loss 0.0371  mean p 0.0100 (true rate 0.0101)  flags 0.0015  precision@0.5 0.677

ALL ASSERTIONS PASSED
```

How to read it:

- **Part 3** is the number to remember: identical marginal rates, but correlated errors make the joint FPR 3.7× the naive product.
- **Part 4:** the brute-force optimum (0.0229) sits next to the analytic t* (0.0196). The cost curve is flat near the optimum, which is why noise moves the argmin slightly. The 0.5 default costs 4.5× more.
- **Part 5:** prior correction is one line of arithmetic and the largest single calibration win in this file.

### 3.2 Softmax, temperature, sampling filters and gradients

```python
"""softmax_temperature_lab.py - softmax, temperature, sampling filters, and the gradients behind training and distillation.

  1. Naive softmax overflows; subtracting the max is exact because softmax is shift-invariant.
  2. Temperature: entropy rises monotonically with T, and dH/dT = Var_p(z) / T^3 (checked by finite differences).
  3. Nucleus (top-p) and min-p kept-set sizes vs T on a Zipf-like 50k vocabulary; filter ORDER matters.
  4. d CE / d logits = softmax - onehot (finite-difference check).
  5. Distillation: soft-target gradients shrink like 1/T^2, which is why the loss is multiplied by T^2.
  6. Multi-label guardrails need independent sigmoids, not one softmax.
  7. Float addition is not associative: "temperature 0" is only as deterministic as the reduction order.
"""
import numpy as np

rng = np.random.default_rng(17)


def softmax(z, T=1.0):
    z = np.asarray(z, dtype=np.float64) / T
    z = z - z.max(axis=-1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=-1, keepdims=True)


def entropy_bits(p):
    p = p[p > 0]
    return float(-(p * np.log2(p)).sum())


print("== 1. overflow and shift invariance ==")
z = np.array([1000.0, 999.0, 998.0])
with np.errstate(over="ignore", invalid="ignore"):
    naive = np.exp(z) / np.exp(z).sum()
print(f"naive exp/sum: {naive}   stable: {softmax(z).round(6)}")
print(f"float16 exp overflows above z = {np.log(np.finfo(np.float16).max):.2f} "
      f"(np.exp(np.float16(11.1)) = {np.exp(np.float16(11.1))})")
zz = rng.standard_normal(10)
print(f"max |softmax(z + 123.4) - softmax(z)| = {np.abs(softmax(zz + 123.4) - softmax(zz)).max():.1e}")
assert np.isnan(naive).all() and np.abs(softmax(zz + 123.4) - softmax(zz)).max() < 1e-12

print("\n== 2-3. temperature on a Zipf-like 50k-token distribution ==")
V = 50_000
logits = -1.1 * np.log(np.arange(1, V + 1)) + 0.3 * rng.standard_normal(V)
logits = logits[rng.permutation(V)]


def top_p_size(p, top_p):
    s = np.sort(p)[::-1]
    return int(np.searchsorted(np.cumsum(s), top_p) + 1)


def min_p_size(p, min_p):
    return int(np.sum(p >= min_p * p.max()))


print(f"{'T':>5} {'H bits':>7} {'perplexity':>10} {'p(top1)':>8} {'top-p .9 keeps':>14} {'min-p .05 keeps':>15}")
Hs = []
for T in (0.1, 0.3, 0.7, 1.0, 1.5, 2.0):
    p = softmax(logits, T)
    H = entropy_bits(p)
    Hs.append(H)
    print(f"{T:>5.1f} {H:>7.3f} {2 ** H:>10.1f} {p.max():>8.4f} {top_p_size(p, 0.9):>14,} {min_p_size(p, 0.05):>15,}")
assert all(a < b for a, b in zip(Hs, Hs[1:]))
print(f"{'T':>5} {'dH/dT finite diff':>18} {'Var_p(z)/T^3':>13}  (nats)")
for T in (0.5, 1.0, 2.0):
    h = 1e-5
    Hn = lambda t: -(softmax(logits, t) * np.log(np.maximum(softmax(logits, t), 1e-300))).sum()
    fd = (Hn(T + h) - Hn(T - h)) / (2 * h)
    p = softmax(logits, T)
    var = (p * logits ** 2).sum() - (p * logits).sum() ** 2
    print(f"{T:>5.1f} {fd:>18.6f} {var / T ** 3:>13.6f}")
    assert abs(fd - var / T ** 3) < 1e-4 * max(1.0, abs(fd))

print("\nfilter order at T = 1.5, top_p = 0.9:")
p_temp_first = softmax(logits, 1.5)
k1 = top_p_size(p_temp_first, 0.9)                       # HF/vLLM order: temperature, then top-k / top-p / min-p
keep = np.argsort(softmax(logits, 1.0))[::-1][:top_p_size(softmax(logits, 1.0), 0.9)]
print(f"  temperature -> top-p keeps {k1:,} tokens; top-p (at T=1) -> temperature keeps {len(keep):,} tokens")
assert k1 != len(keep)

print("\n== 4. gradient of cross-entropy w.r.t. logits ==")
zc = rng.standard_normal(7)
y = 3
ce = lambda v: -np.log(softmax(v)[y])
fd = np.array([(ce(zc + 1e-6 * e) - ce(zc - 1e-6 * e)) / 2e-6 for e in np.eye(7)])
analytic = softmax(zc) - np.eye(7)[y]
print(f"max |finite diff - (softmax - onehot)| = {np.abs(fd - analytic).max():.1e}")
assert np.abs(fd - analytic).max() < 1e-8

print("\n== 5. distillation: gradient of soft-target CE shrinks like 1/T^2 ==")
zt, zs = 3 * rng.standard_normal(100), 3 * rng.standard_normal(100)
print(f"{'T':>4} {'||grad||':>10} {'||grad|| * T^2':>15}")
g_scaled = []
for T in (1, 2, 4, 8, 16):
    g = (softmax(zs, T) - softmax(zt, T)) / T                  # d/dz_s of CE(p_t(T), p_s(T))
    g_scaled.append(np.linalg.norm(g) * T ** 2)
    print(f"{T:>4} {np.linalg.norm(g):>10.6f} {g_scaled[-1]:>15.6f}")
assert abs(g_scaled[-1] / g_scaled[-2] - 1) < 0.05

print("\n== 6. multi-label guardrail: one prompt that is BOTH PII-leaking and toxic ==")
labels = ["pii", "toxic", "jailbreak", "benign"]
head = np.array([2.1, 2.1, -3.0, -1.0])                           # what a trained head might emit for that prompt
p_soft = softmax(head)
p_sig = 1 / (1 + np.exp(-head))
print("softmax:  " + "  ".join(f"{l}={v:.2f}" for l, v in zip(labels, p_soft)) + "   -> at threshold 0.5 flags: "
      + str([l for l, v in zip(labels, p_soft) if v > 0.5]))
print("sigmoids: " + "  ".join(f"{l}={v:.2f}" for l, v in zip(labels, p_sig)) + "   -> at threshold 0.5 flags: "
      + str([l for l, v in zip(labels, p_sig) if v > 0.5]))
assert sum(p_soft > 0.5) == 0 and sum(p_sig > 0.5) == 2

print("\n== 7. reduction order changes logits (why temperature 0 is not automatically deterministic) ==")
h = rng.standard_normal(4096).astype(np.float32)
W = (rng.standard_normal((4096, 2000)) / 64).astype(np.float32)
full = h @ W
split = sum((h[i:i + 512] @ W[i:i + 512] for i in range(0, 4096, 512)), np.zeros(2000, np.float32))
rev = sum((h[i:i + 512] @ W[i:i + 512] for i in reversed(range(0, 4096, 512))), np.zeros(2000, np.float32))
print(f"max |logit difference| between three reduction orders: {max(np.abs(full - split).max(), np.abs(split - rev).max()):.2e}")
a, b, c = np.float32(1e8), np.float32(-1e8), np.float32(1.0)
print(f"(a + b) + c = {(a + b) + c}   a + (b + c) = {a + (b + c)}   (float32)")
gaps = np.sort(full)[-1] - np.sort(full)[-2]
print(f"this step's top-2 logit gap {gaps:.2e}: greedy decoding flips whenever a gap falls below the reduction noise")
assert (a + b) + c != a + (b + c)
print("\nALL ASSERTIONS PASSED")
```

Output (verified; the overflow warning goes to stderr):

```text
== 1. overflow and shift invariance ==
naive exp/sum: [nan nan nan]   stable: [0.665241 0.244728 0.090031]
float16 exp overflows above z = 11.09 (np.exp(np.float16(11.1)) = inf)
max |softmax(z + 123.4) - softmax(z)| = 1.4e-15

== 2-3. temperature on a Zipf-like 50k-token distribution ==
    T  H bits perplexity  p(top1) top-p .9 keeps min-p .05 keeps
  0.1   0.590        1.5   0.8726              2               2
  0.3   1.632        3.1   0.5596              3               3
  0.7   4.708       26.1   0.2462             46              13
  1.0   9.602      777.1   0.0864          7,664              19
  1.5  14.089    17427.0   0.0111         33,510              97
  2.0  15.032    33502.9   0.0027         38,916             373
    T  dH/dT finite diff  Var_p(z)/T^3  (nats)
  0.5           4.922083      4.922083
  1.0          11.291222     11.291222
  2.0           0.629468      0.629468

filter order at T = 1.5, top_p = 0.9:
  temperature -> top-p keeps 33,510 tokens; top-p (at T=1) -> temperature keeps 7,664 tokens

== 4. gradient of cross-entropy w.r.t. logits ==
max |finite diff - (softmax - onehot)| = 1.4e-10

== 5. distillation: gradient of soft-target CE shrinks like 1/T^2 ==
   T   ||grad||  ||grad|| * T^2
   1   0.491734        0.491734
   2   0.123347        0.493386
   4   0.027121        0.433939
   8   0.006145        0.393281
  16   0.001468        0.375685

== 6. multi-label guardrail: one prompt that is BOTH PII-leaking and toxic ==
softmax:  pii=0.49  toxic=0.49  jailbreak=0.00  benign=0.02   -> at threshold 0.5 flags: []
sigmoids: pii=0.89  toxic=0.89  jailbreak=0.05  benign=0.27   -> at threshold 0.5 flags: ['pii', 'toxic']

== 7. reduction order changes logits (why temperature 0 is not automatically deterministic) ==
max |logit difference| between three reduction orders: 3.34e-06
(a + b) + c = 1.0   a + (b + c) = 0.0   (float32)
this step's top-2 logit gap 2.30e-01: greedy decoding flips whenever a gap falls below the reduction noise

ALL ASSERTIONS PASSED
```

How to read it:

- **Part 2–3 table:** temperature changes the perplexity of the *sampling distribution* from 1.5 to 33,503. That's the "creativity" knob in numbers. The top-p and min-p columns show why min-p is the safer filter at high T.
- **Part 5:** the T² factor isn't folklore. The measured gradient norm × T² flattens to a constant as T grows.
- **Part 7:** the reduction-order noise (3.3e-6 here) is tiny next to this step's top-2 gap (0.23). Over a 1,000-token generation, though, some step will have a near-tie, and that's all it takes to diverge.

### 3.3 Entropy, KL, JS, MLE and the KL-regularized optimum

```python
"""entropy_kl_ce_identities.py - entropy, cross-entropy, KL and JS: the identities behind LM loss, distillation and RLHF.

  1. H(uniform over K) = log K; bits = nats / ln 2; perplexity = exp(cross-entropy).
  2. H(p, q) = H(p) + KL(p || q), and KL >= 0 (Gibbs) - on 20,000 random pairs.
  3. KL is asymmetric and explodes where q ~ 0 but p > 0.
  4. Fitting one Gaussian to a bimodal target: forward KL covers both modes, reverse KL locks onto one.
  5. JS divergence is symmetric and bounded by ln 2.
  6. MLE == minimizing cross-entropy: gradient descent on CE recovers empirical token frequencies.
  7. KL-regularized reward maximization has the closed form pi* ~ pi_ref * exp(r / beta) (the RLHF/DPO core).
"""
import numpy as np

rng = np.random.default_rng(19)


def H(p):
    p = p[p > 0]
    return float(-(p * np.log(p)).sum())


def CE(p, q):
    m = p > 0
    return float(-(p[m] * np.log(q[m])).sum())


def KL(p, q):
    m = p > 0
    return float((p[m] * np.log(p[m] / q[m])).sum())


def softmax(z):
    e = np.exp(z - z.max())
    return e / e.sum()


print("== 1. units ==")
for K in (2, 32_000, 128_000):
    print(f"uniform over K={K:>7,}: H = {H(np.full(K, 1 / K)):.4f} nats = {H(np.full(K, 1 / K)) / np.log(2):.3f} bits "
          f"(log2 K = {np.log2(K):.3f}); perplexity {np.exp(H(np.full(K, 1 / K))):,.0f}")
for ce in (1.5, 2.0, 2.5):
    print(f"LM loss {ce} nats/token = {ce / np.log(2):.3f} bits/token -> perplexity {np.exp(ce):.2f}")

print("\n== 2. H(p,q) = H(p) + KL(p||q) and Gibbs' inequality ==")
worst, min_kl = 0.0, np.inf
for _ in range(20_000):
    k = rng.integers(2, 50)
    p, q = rng.dirichlet(np.ones(k) * 0.5), rng.dirichlet(np.ones(k) * 0.5)
    worst = max(worst, abs(CE(p, q) - (H(p) + KL(p, q))))
    min_kl = min(min_kl, KL(p, q))
print(f"max |H(p,q) - H(p) - KL(p||q)| = {worst:.2e};  min KL over 20k random pairs = {min_kl:.2e} (>= 0)")
assert worst < 1e-10 and min_kl >= 0

print("\n== 3. asymmetry and the zero-forcing blow-up ==")
p = np.array([0.5, 0.49, 0.01])
q = np.array([0.98, 0.01, 0.01])
print(f"KL(p||q) = {KL(p, q):.4f}  KL(q||p) = {KL(q, p):.4f}")
for eps in (1e-2, 1e-4, 1e-8):
    q2 = np.array([1 - eps, eps / 2, eps / 2])
    print(f"  q puts {eps:.0e} on tokens where p puts 0.5: KL(p||q) = {KL(p, q2):8.3f}, KL(q||p) = {KL(q2, p):.3f}")

print("\n== 4. one Gaussian vs a bimodal target (grid search over mu, sigma) ==")
x = np.linspace(-8, 8, 4001)
dx = x[1] - x[0]
gauss = lambda m, s: np.exp(-0.5 * ((x - m) / s) ** 2) / (s * np.sqrt(2 * np.pi))
target = 0.5 * gauss(-3, 0.7) + 0.5 * gauss(3, 0.7)
best = {"forward KL(p||q)": (np.inf, None), "reverse KL(q||p)": (np.inf, None)}
for m in np.linspace(-4, 4, 161):
    for s in np.linspace(0.3, 5, 95):
        q = gauss(m, s) + 1e-300
        f = np.sum(target * np.log((target + 1e-300) / q)) * dx
        r = np.sum(q * np.log(q / (target + 1e-300))) * dx
        if f < best["forward KL(p||q)"][0]:
            best["forward KL(p||q)"] = (f, (m, s))
        if r < best["reverse KL(q||p)"][0]:
            best["reverse KL(q||p)"] = (r, (m, s))
for k_, (v, (m, s)) in best.items():
    print(f"{k_:17s} best mu = {m:+.2f}, sigma = {s:.2f}  (divergence {v:.3f})")
assert abs(best["forward KL(p||q)"][1][0]) < 0.2 and abs(abs(best["reverse KL(q||p)"][1][0]) - 3) < 0.2

print("\n== 5. Jensen-Shannon ==")
js = lambda p, q: 0.5 * KL(p, (p + q) / 2) + 0.5 * KL(q, (p + q) / 2)
p, q = np.array([1.0, 0.0]), np.array([0.0, 1.0])
print(f"JS of disjoint supports = {js(p, q):.6f} = ln 2 = {np.log(2):.6f}; KL there is infinite")
vals = [(lambda a, b: (js(a, b), js(b, a)))(rng.dirichlet(np.ones(8)), rng.dirichlet(np.ones(8))) for _ in range(1000)]
print(f"max |JS(p,q) - JS(q,p)| over 1000 pairs = {max(abs(a - b) for a, b in vals):.1e}")
assert abs(js(p, q) - np.log(2)) < 1e-12

print("\n== 6. MLE == cross-entropy minimization (a unigram 'language model') ==")
true = rng.dirichlet(np.ones(20) * 0.3)
tokens = rng.choice(20, 50_000, p=true)
freq = np.bincount(tokens, minlength=20) / len(tokens)
z = np.zeros(20)
for _ in range(20_000):
    z -= 3.0 * (softmax(z) - freq)                 # gradient of mean CE over the tokens = softmax(z) - empirical freq
q = softmax(z)
print(f"max |model p - empirical freq| = {np.abs(q - freq).max():.2e}")
print(f"train CE = {CE(freq, q):.4f} nats = H(empirical) {H(freq):.4f}  -> perplexity {np.exp(CE(freq, q)):.3f}; "
      f"uniform model perplexity {np.exp(CE(freq, np.full(20, 1 / 20))):.3f}")
assert np.abs(q - freq).max() < 1e-4

print("\n== 7. KL-regularized policy optimum (5 candidate responses) ==")
pi_ref = np.array([0.40, 0.30, 0.15, 0.10, 0.05])
reward = np.array([0.0, 0.5, 1.0, 2.0, 3.0])
print(f"{'beta':>6} {'closed form pi* ~ pi_ref*exp(r/beta)':>40} {'gradient ascent':>32} {'E[r]':>6} {'KL':>6}")
for beta in (0.1, 0.5, 1.0, 5.0):
    closed = pi_ref * np.exp(reward / beta)
    closed /= closed.sum()
    theta = np.log(pi_ref).copy()
    for _ in range(20_000):
        pi = softmax(theta)
        obj_grad = reward - beta * (np.log(pi / pi_ref) + 1)       # d/dpi of E[r] - beta*KL
        theta += 0.05 * pi * (obj_grad - (pi * obj_grad).sum())   # chain rule through softmax
    pi = softmax(theta)
    print(f"{beta:>6.1f} {str(closed.round(3)):>40} {str(pi.round(3)):>32} {(pi * reward).sum():>6.3f} {KL(pi, pi_ref):>6.3f}")
    assert np.abs(pi - closed).max() < 1e-3
print("beta -> 0 collapses onto the highest reward (reward hacking); beta -> inf stays at pi_ref.")
print("DPO rearranges the same optimum: r(y) = beta * log(pi*(y) / pi_ref(y)) + beta * log Z.")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. units ==
uniform over K=      2: H = 0.6931 nats = 1.000 bits (log2 K = 1.000); perplexity 2
uniform over K= 32,000: H = 10.3735 nats = 14.966 bits (log2 K = 14.966); perplexity 32,000
uniform over K=128,000: H = 11.7598 nats = 16.966 bits (log2 K = 16.966); perplexity 128,000
LM loss 1.5 nats/token = 2.164 bits/token -> perplexity 4.48
LM loss 2.0 nats/token = 2.885 bits/token -> perplexity 7.39
LM loss 2.5 nats/token = 3.607 bits/token -> perplexity 12.18

== 2. H(p,q) = H(p) + KL(p||q) and Gibbs' inequality ==
max |H(p,q) - H(p) - KL(p||q)| = 3.55e-15;  min KL over 20k random pairs = 1.38e-06 (>= 0)

== 3. asymmetry and the zero-forcing blow-up ==
KL(p||q) = 1.5705  KL(q||p) = 0.6206
  q puts 1e-02 on tokens where p puts 0.5: KL(p||q) =    1.912, KL(q||p) = 0.650
  q puts 1e-04 on tokens where p puts 0.5: KL(p||q) =    4.210, KL(q||p) = 0.692
  q puts 1e-08 on tokens where p puts 0.5: KL(p||q) =    8.815, KL(q||p) = 0.693

== 4. one Gaussian vs a bimodal target (grid search over mu, sigma) ==
forward KL(p||q)  best mu = +0.00, sigma = 3.10  (divergence 0.789)
reverse KL(q||p)  best mu = +3.00, sigma = 0.70  (divergence 0.693)

== 5. Jensen-Shannon ==
JS of disjoint supports = 0.693147 = ln 2 = 0.693147; KL there is infinite
max |JS(p,q) - JS(q,p)| over 1000 pairs = 0.0e+00

== 6. MLE == cross-entropy minimization (a unigram 'language model') ==
max |model p - empirical freq| = 1.45e-05
train CE = 2.3289 nats = H(empirical) 2.3289  -> perplexity 10.267; uniform model perplexity 20.000

== 7. KL-regularized policy optimum (5 candidate responses) ==
  beta     closed form pi* ~ pi_ref*exp(r/beta)                  gradient ascent   E[r]     KL
   0.1                         [0. 0. 0. 0. 1.]  [0.    0.    0.    0.001 0.999]  2.998  2.985
   0.5          [0.014 0.029 0.04  0.195 0.722]  [0.014 0.029 0.04  0.195 0.722]  2.610  1.888
   1.0          [0.131 0.162 0.134 0.243 0.33 ]  [0.131 0.162 0.134 0.243 0.33 ]  1.690  0.576
   5.0          [0.346 0.287 0.159 0.129 0.079]  [0.346 0.287 0.159 0.129 0.079]  0.797  0.015
beta -> 0 collapses onto the highest reward (reward hacking); beta -> inf stays at pi_ref.
DPO rearranges the same optimum: r(y) = beta * log(pi*(y) / pi_ref(y)) + beta * log Z.

ALL ASSERTIONS PASSED
```

How to read it:

- **Part 3** is the zero-avoiding blow-up in four lines. That's why distillation from a teacher that assigns ~0 to tokens the data contains (or the reverse) produces huge, unstable gradients, and why smoothing or temperature is applied first.
- **Part 4** is the forward/reverse picture as numbers: μ = 0 with σ = 3.1 (spread over both modes), vs μ = 3 with σ = 0.7 (one mode exactly).
- **Part 7:** the closed form and 20,000 steps of gradient ascent agree to 3 decimals at every β. The E[r] and KL columns are the reward/leash trade-off you tune in RLHF.

### 3.4 Calibration: temperature scaling, reliability, selective prediction, judge calibration

```python
"""temperature_scaling_calibration.py - calibrating an overconfident classifier and a biased LLM-as-judge.

  1. Temperature scaling (Guo et al., 2017): one scalar T fitted on validation NLL. Accuracy cannot change
     (argmax is invariant to T); NLL and ECE drop.
  2. Reliability table before and after.
  3. Selective prediction: once calibrated, "escalate when confidence < t" gives a predictable coverage/accuracy.
  4. A judge whose P(yes) is shifted (says "yes" too often) is NOT fixed by a temperature; Platt scaling
     (a*logit + b) fixes it.
"""
import numpy as np
from sklearn.linear_model import LogisticRegression

rng = np.random.default_rng(23)
K, N = 10, 30_000


def softmax(z):
    z = z - z.max(axis=1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=1, keepdims=True)


def nll(p, y):
    return float(-np.mean(np.log(p[np.arange(len(y)), y] + 1e-12)))


def ece(conf, correct, bins=15):
    edges = np.linspace(0, 1, bins + 1)
    total = 0.0
    for lo, hi in zip(edges[:-1], edges[1:]):
        m = (conf > lo) & (conf <= hi)
        if m.any():
            total += m.mean() * abs(conf[m].mean() - correct[m].mean())
    return total


def golden(f, lo, hi, iters=80):
    g = (np.sqrt(5) - 1) / 2
    a, b = lo, hi
    for _ in range(iters):
        c, d = b - g * (b - a), a + g * (b - a)
        if f(c) < f(d):
            b = d
        else:
            a = c
    return (a + b) / 2


# ground truth: per-example true logits; labels drawn from softmax(true logits)
true_logits = 1.0 * rng.standard_normal((N, K)) + np.where(np.arange(K) == rng.integers(0, K, N)[:, None], 4.0, 0)
y = np.array([rng.choice(K, p=p) for p in softmax(true_logits)])
model_logits = 2.0 * true_logits + 0.3 * rng.standard_normal((N, K))      # overconfident (as deep nets typically are)
val, test = slice(0, N // 2), slice(N // 2, N)

logT = golden(lambda lt: nll(softmax(model_logits[val] / np.exp(lt)), y[val]), np.log(0.05), np.log(20))
T = float(np.exp(logT))
print(f"== 1. fitted temperature T = {T:.3f} (on {N // 2:,} validation examples) ==")
for name, z in (("uncalibrated", model_logits[test]), ("temperature-scaled", model_logits[test] / T)):
    p = softmax(z)
    conf, pred = p.max(1), p.argmax(1)
    correct = pred == y[test]
    print(f"{name:19s} accuracy {correct.mean():.4f}  NLL {nll(p, y[test]):.4f}  ECE {ece(conf, correct):.4f}  "
          f"mean confidence {conf.mean():.4f}")
acc_before = np.mean(model_logits[test].argmax(1) == y[test])
acc_after = np.mean((model_logits[test] / T).argmax(1) == y[test])
assert acc_before == acc_after and T > 1.5

print("\n== 2. reliability table (test) ==")
print(f"{'confidence bin':>15} | {'n':>5} {'conf':>6} {'acc':>6} (before) | {'n':>5} {'conf':>6} {'acc':>6} (after)")
pb, pa = softmax(model_logits[test]), softmax(model_logits[test] / T)
cb, ca = pb.max(1), pa.max(1)
okb, oka = pb.argmax(1) == y[test], pa.argmax(1) == y[test]
for lo, hi in ((0.0, 0.4), (0.4, 0.6), (0.6, 0.8), (0.8, 0.9), (0.9, 0.99), (0.99, 1.0)):
    mb, ma = (cb > lo) & (cb <= hi), (ca > lo) & (ca <= hi)
    fmt = lambda m, c, ok: f"{m.sum():>5} {c[m].mean() if m.any() else float('nan'):>6.3f} {ok[m].mean() if m.any() else float('nan'):>6.3f}"
    print(f"{f'({lo:.2f}, {hi:.2f}]':>15} | {fmt(mb, cb, okb)}          | {fmt(ma, ca, oka)}")

print("\n== 3. selective prediction: answer locally if calibrated confidence >= t, else escalate ==")
print(f"{'t':>5} {'coverage':>9} {'accuracy on answered':>21} {'expected (mean conf)':>21}")
for t in (0.0, 0.5, 0.7, 0.9, 0.95):
    m = ca >= t
    print(f"{t:>5.2f} {m.mean():>9.3f} {oka[m].mean():>21.3f} {ca[m].mean():>21.3f}")
    if t >= 0.5 and m.sum() > 500:
        assert abs(oka[m].mean() - ca[m].mean()) < 0.03

print("\n== 4. LLM-as-judge: P(yes) from logprobs, biased toward 'yes' ==")
n = 20_000
truth = rng.random(n) < 0.3                                       # 30% of answers are actually acceptable
true_logit = np.where(truth, 1.5, -1.5) + rng.standard_normal(n)
p_true = 1 / (1 + np.exp(-true_logit))
label = rng.random(n) < p_true                                    # human verdicts consistent with the true score
judge_logit = 1.8 * true_logit + 2.0                              # overconfident AND shifted toward "yes"
v, t_ = slice(0, n // 2), slice(n // 2, n)
sig = lambda z: 1 / (1 + np.exp(-z))
bnll = lambda p, yy: float(-np.mean(np.where(yy, np.log(p + 1e-12), np.log(1 - p + 1e-12))))
Tj = float(np.exp(golden(lambda lt: bnll(sig(judge_logit[v] / np.exp(lt)), label[v]), np.log(0.05), np.log(20))))
platt = LogisticRegression(C=1e6).fit(judge_logit[v, None], label[v])   # Platt scaling = 1-feature logistic regression
a, b = float(platt.coef_[0, 0]), float(platt.intercept_[0])
for name, p in (("raw judge", sig(judge_logit[t_])), (f"temperature T={Tj:.2f}", sig(judge_logit[t_] / Tj)),
                (f"Platt a={a:.2f} b={b:+.2f}", sig(a * judge_logit[t_] + b))):
    print(f"{name:24s} mean P(yes) {p.mean():.3f} (human yes-rate {label[t_].mean():.3f})  NLL {bnll(p, label[t_]):.4f}  "
          f"ECE {ece(np.maximum(p, 1 - p), (p > 0.5) == label[t_]):.4f}")
assert bnll(sig(a * judge_logit[t_] + b), label[t_]) < bnll(sig(judge_logit[t_] / Tj), label[t_])
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. fitted temperature T = 2.012 (on 15,000 validation examples) ==
uncalibrated        accuracy 0.7563  NLL 1.2838  ECE 0.1823  mean confidence 0.9386
temperature-scaled  accuracy 0.7563  NLL 0.9210  ECE 0.0088  mean confidence 0.7504

== 2. reliability table (test) ==
 confidence bin |     n   conf    acc (before) |     n   conf    acc (after)
   (0.00, 0.40] |    78  0.336  0.167          |   683  0.331  0.350
   (0.40, 0.60] |   429  0.517  0.312          |  2251  0.514  0.528
   (0.60, 0.80] |   916  0.715  0.476          |  4947  0.714  0.723
   (0.80, 0.90] |  1220  0.858  0.552          |  3919  0.853  0.850
   (0.90, 0.99] |  5702  0.964  0.722          |  3181  0.937  0.939
   (0.99, 1.00] |  6655  0.997  0.897          |    19  0.992  1.000

== 3. selective prediction: answer locally if calibrated confidence >= t, else escalate ==
    t  coverage  accuracy on answered  expected (mean conf)
 0.00     1.000                 0.756                 0.750
 0.50     0.895                 0.795                 0.791
 0.70     0.674                 0.853                 0.850
 0.90     0.213                 0.939                 0.938
 0.95     0.067                 0.971                 0.966

== 4. LLM-as-judge: P(yes) from logprobs, biased toward 'yes' ==
raw judge                mean P(yes) 0.561 (human yes-rate 0.387)  NLL 0.6516  ECE 0.1024
temperature T=2.44       mean P(yes) 0.560 (human yes-rate 0.387)  NLL 0.5482  ECE 0.0335
Platt a=0.54 b=-1.12     mean P(yes) 0.384 (human yes-rate 0.387)  NLL 0.4581  ECE 0.0109

ALL ASSERTIONS PASSED
```

How to read it:

- **Accuracy is identical** before and after (0.7563). Temperature scaling is a pure confidence fix, so it can be applied safely to any deployed classifier.
- **The reliability table** shows the classic overconfidence signature: before scaling, the 0.99+ bin is 89.7% accurate. After, every populated bin's accuracy matches its confidence within ~2 points.
- **The judge block:** temperature fixes the slope, Platt fixes slope *and* intercept. Only Platt brings the judge's yes-rate (0.384) to the human rate (0.387).

### 3.5 Semantic entropy: a blueprint for confabulation detection

```python
"""semantic_entropy_blueprint.py - naive vs semantic entropy for confabulation detection, on a seeded answer simulator.

Pipeline (Farquhar et al., Nature 2024): sample N answers -> cluster by bidirectional entailment -> entropy over
clusters. Here the "LLM" is a simulator and the entailment check is a canonicalizer (alias table), so the code
runs offline; in production swap in sampled LLM answers and an NLI model or an LLM entailment judge.
  1. Paraphrases inflate naive (string-level) entropy for questions the model actually knows.
  2. Semantic entropy separates known from confabulated answers far better (AUROC).
  3. Over-merging clusters (a lossy equivalence check) silently hides uncertainty.
  4. Cost: N samples + up to N(N-1)/2 entailment checks per question.
"""
import itertools
import re

import numpy as np

rng = np.random.default_rng(29)
N_Q, N_SAMPLES = 600, 10

SURFACES = ["{a}", "{a}.", "The answer is {a}.", "It's {a}", "I believe it is {a}.", "{A}"]


def make_meanings(qid, k):
    return [f"answer{qid}_{j}" for j in range(k)]


def sample_answers(known, meanings, n):
    """Known: the correct meaning (index 0) with prob 0.85. Unknown: spread over 5 meanings (confabulation)."""
    if known:
        probs = np.array([0.85, 0.10, 0.05, 0, 0, 0])[: len(meanings)]
    else:
        probs = np.array([0.28, 0.22, 0.2, 0.16, 0.14, 0])[: len(meanings)]
    probs = probs / probs.sum()
    picks = rng.choice(len(meanings), n, p=probs)
    outs = []
    for m in picks:
        tpl = SURFACES[rng.integers(0, len(SURFACES))]
        outs.append(tpl.format(a=meanings[m], A=meanings[m].upper()))
    return outs, picks


def canonical(text):
    """Stand-in for 'A entails B and B entails A': strip templates, case and punctuation."""
    t = text.lower().strip().rstrip(".")
    t = re.sub(r"^(the answer is|it's|i believe it is)\s+", "", t)
    return t


def clusters(answers, same):
    reps, ids, checks = [], [], 0
    for a in answers:                                   # greedy clustering: compare with one member per cluster
        for ci, r in enumerate(reps):
            checks += 1
            if same(a, r):
                ids.append(ci)
                break
        else:
            reps.append(a)
            ids.append(len(reps) - 1)
    return np.array(ids), checks


def entropy_from_ids(ids):
    _, counts = np.unique(ids, return_counts=True)
    p = counts / counts.sum()
    return float(-(p * np.log(p)).sum())


def auroc(score, positive):
    """P(score of a random positive > score of a random negative), ties count half."""
    pos, neg = score[positive], score[~positive]
    diff = pos[:, None] - neg[None, :]
    return float((diff > 0).mean() + 0.5 * (diff == 0).mean())


naive, semantic, merged, wrong, checks_all = [], [], [], [], []
for q in range(N_Q):
    known = rng.random() < 0.6
    meanings = make_meanings(q, 6)
    answers, picks = sample_answers(known, meanings, N_SAMPLES)
    ids, checks = clusters(answers, lambda a, b: canonical(a) == canonical(b))
    checks_all.append(checks)
    mode_cluster = np.bincount(ids).argmax()
    answer_meaning = picks[ids == mode_cluster][0]
    wrong.append(answer_meaning != 0)                   # meaning 0 is the correct one
    naive.append(entropy_from_ids(np.unique(answers, return_inverse=True)[1]))
    semantic.append(entropy_from_ids(ids))
    # a lossy equivalence check that merges meanings 0..2 (e.g. "1912" == "April 1912" == "the 1910s")
    lossy = lambda a, b: canonical(a).rsplit("_", 1)[0] == canonical(b).rsplit("_", 1)[0] and \
        min(int(canonical(a).rsplit("_", 1)[1]), 3) == min(int(canonical(b).rsplit("_", 1)[1]), 3)
    merged.append(entropy_from_ids(clusters(answers, lossy)[0]))

naive, semantic, merged, wrong = map(np.array, (naive, semantic, merged, wrong))
print(f"{N_Q} questions, {N_SAMPLES} samples each; final answer = largest meaning cluster; "
      f"wrong-answer rate {wrong.mean():.3f}")
print(f"\n{'signal':34s} {'AUROC (detect wrong)':>21} {'mean | right':>13} {'mean | wrong':>13}")
for name, s in (("naive entropy over exact strings", naive), ("semantic entropy over meanings", semantic),
                ("semantic entropy, over-merged", merged)):
    print(f"{name:34s} {auroc(s, wrong):>21.3f} {s[~wrong].mean():>13.3f} {s[wrong].mean():>13.3f}")
assert auroc(semantic, wrong) > auroc(naive, wrong) + 0.05 and auroc(merged, wrong) < auroc(semantic, wrong)

print("\n== abstention: escalate / say 'I don't know' when semantic entropy > threshold ==")
print(f"{'threshold':>9} {'answered':>9} {'error rate on answered':>23}")
for thr in (np.inf, 1.2, 0.9, 0.6):
    m = semantic <= thr
    print(f"{thr:>9} {m.mean():>9.3f} {wrong[m].mean():>23.3f}")

pairs = N_SAMPLES * (N_SAMPLES - 1) // 2
print(f"\ncost per question: {N_SAMPLES} generations + {np.mean(checks_all):.1f} entailment checks "
      f"(greedy clustering; worst case all-pairs = {pairs}); one call of the plain pipeline = 1 generation")
assert len(list(itertools.combinations(range(N_SAMPLES), 2))) == pairs
print("\nALL ASSERTIONS PASSED")
```

Output (verified, on the seeded simulator):

```text
600 questions, 10 samples each; final answer = largest meaning cluster; wrong-answer rate 0.283

signal                              AUROC (detect wrong)  mean | right  mean | wrong
naive entropy over exact strings                   0.843         1.774         2.087
semantic entropy over meanings                     0.896         0.592         1.346
semantic entropy, over-merged                      0.883         0.565         1.194

== abstention: escalate / say 'I don't know' when semantic entropy > threshold ==
threshold  answered  error rate on answered
      inf     1.000                   0.283
      1.2     0.647                   0.082
      0.9     0.552                   0.006
      0.6     0.403                   0.000

cost per question: 10 generations + 14.6 entailment checks (greedy clustering; worst case all-pairs = 45); one call of the plain pipeline = 1 generation

ALL ASSERTIONS PASSED
```

How to read it:

- **Swap in real components** without touching the scoring code. `sample_answers` becomes N calls to your model (temperature 1, or the provider default, which is now the only option on current Claude models). `canonical(a) == canonical(b)` becomes "NLI(a ⇒ b) and NLI(b ⇒ a)", or an LLM judge asked about mutual entailment.
- **The over-merge row** is the main design risk. An entailment check that's too lenient merges distinct answers and hides uncertainty (AUROC 0.896 → 0.883 here). Audit the clustering on a labelled sample before trusting the score.
- **Cost** is linear in N for generation and up to quadratic for entailment. Greedy clustering against one representative per cluster cuts the checks from 45 to ~15.

---

## 4. The Andrew Ng Lens: Probability-Aware Evals and Error Analysis

### 4.1 Evaluate at production prevalence, or reweight

A guardrail eval set is usually *enriched*: half attacks, half benign, because attacks are rare. Precision measured on it is meaningless for production (§1.2), since at 50/50 a TPR 0.99 / FPR 0.01 detector has precision 0.99, and at 0.1% it has 0.09. Ng's dev/test rule (dev and test sets should reflect the data you expect to get in the future) applies directly. Either sample the eval from production traffic, or keep the enriched set and **reweight to the production prior** when computing precision, alert volume and cost. Recall and FPR are prevalence-free, so report them as the model's properties. Precision and cost are deployment properties.

### 4.2 The error-analysis spreadsheet for a guardrail

For each false positive and false negative in a sample of ~200, record:

| request (redacted) | label | score (calibrated) | stage that fired | category | tag |
|---|---|---:|---|---|---|

Tags that recur in practice, and the lever each one points to:

| Tag | Lever |
|---|---|
| `benign-security-content` (pentest docs, CVE discussions) | Hard benign examples in training; it's the correlated-error source of §1.2 |
| `fiction/roleplay` | Policy clarification first (is it actually allowed?), then data |
| `obfuscation` (encoding, leetspeak, split tokens) | Normalization pre-processing; adversarial augmentation |
| `multi-label` (PII *and* toxic) | Independent sigmoids (§1.15) |
| `miscalibrated-high` (confident and wrong) | Temperature/Platt scaling; check for prior shift (§1.4) |
| `label-disagreement` | Fix the policy definition and relabel. Ng's data-centric rule again |

### 4.3 Bayes error and avoidable bias for subjective tasks

Ng's bias/variance analysis compares training error to *human-level performance* as a proxy for the Bayes error. For guardrails and LLM-as-judge, measure that proxy explicitly: have two humans label the same 200 items and compute their agreement. If humans agree 88% of the time, a judge at 86% agreement with humans has little avoidable bias left. Spend effort on calibration and policy clarity, not on a bigger judge. If humans agree 97% and the judge is at 86%, that's an 11-point avoidable-bias gap: improve the judge's prompt, the model or fine-tuning.

### 4.4 Evaluation-driven development, probability edition

1. Write down **C_FP and C_FN** with the product owner before training anything. They set t*.
2. Build the eval at production prevalence (or a reweighting plan) *plus* a hard-benign set.
3. Calibrate (temperature or Platt) on a held-out split, never on the test set.
4. Report recall, FPR, calibrated precision at production prevalence, ECE, and expected cost per 1M requests at t*.
5. Re-run the whole sheet whenever the model, the prompt (for LLM judges), the policy or the traffic mix changes.

Ng's letter separates objective metrics (implemented in code) from subjective ones (LLM-as-judge). The subjective ones are exactly where the calibration of §1.13 decides whether the eval itself can be trusted.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | A "99% accurate" guardrail floods users with false blocks | Precision ≈ 0.09 at 0.1% prevalence | Base-rate neglect (§1.2) | Staged design; cost-derived threshold; prior correction | Report precision at *production* prevalence in every eval |
| F2 | Two-stage guardrail's false-positive rate is several times the design target | Joint FPR 0.373% vs 0.100% assumed | Correlated stage errors (shared hard inputs) | Measure joint FPR on held-out benign traffic; decorrelate with different features or models | Never multiply marginal rates in a design doc |
| F3 | Blocking at 0.5 misses most attacks, or blocks too much | Expected cost far above the optimum | Threshold not derived from costs (§1.3) | t* = C_FP/(C_FP + C_FN) on calibrated scores | Costs written in the design doc; threshold derived from them |
| F4 | A classifier trained on balanced data flags 16% of production | Mean predicted probability ≫ true rate | Prior (label) shift (§1.4) | Closed-form prior correction | Compare mean predicted p with the observed base rate daily |
| F5 | Confident predictions are wrong far more often than the confidence says | ECE high; the 0.99+ bin is 90% accurate | Overconfidence (Guo et al.) | Temperature scaling on a held-out split | ECE + reliability table in model cards |
| F6 | LLM judge says "pass" far more often than humans | Mean P(yes) 0.56 vs human 0.39 | Intercept bias, which temperature can't fix | Platt scaling on human labels | Judge calibration check before each eval run |
| F7 | A doubly violating prompt passes the policy filter | Softmax probabilities split between labels | Softmax used for a multi-label task (§1.15) | One sigmoid per label, BCE loss, per-label thresholds | Architecture review: "can two labels be true at once?" |
| F8 | "Same" sampling settings give different text on another stack | Different kept-token counts | Filter order differs (temperature before or after top-p) | Match the order explicitly (HF: temperature → top-k → top-p → min-p) | Sampling config tests with a fixed seed across stacks |
| F9 | Temperature-0 outputs differ between runs | Divergence after a long identical prefix | Batch-variant kernels + non-associative float sums | Batch-invariant kernels where truly needed; otherwise design for variance | Tests compare semantics, not bytes; cache final answers |
| F10 | Calls to current Claude models fail with 400 after an SDK upgrade | `temperature` / `top_p` / `top_k` in the request | API version `2026-10-21` removed sampling parameters | Remove them; get consistency from structured outputs, validation, voting | Lint for sampling params in Claude request builders |
| F11 | Hallucination detector built on log-probs can't be deployed | Provider returns no log-probs (or rejects them for reasoning models) | Signal availability not checked | Sampling + semantic clustering, or a probe on a self-hosted model | Availability matrix per provider and model in the design doc |
| F12 | Semantic-entropy gate misses obvious confabulations | Distinct answers merged into one cluster | Over-lenient equivalence check | Stricter bidirectional entailment; audit cluster purity | Labelled cluster-purity check before rollout |
| F13 | Distillation diverges or the student ignores soft targets | Huge KL on near-zero teacher probabilities; soft-loss gradient vanishing at high T | Zero-avoiding forward KL; missing T² factor | Temperature-soften both; multiply the soft loss by T² | Unit test: gradient-norm ratio across T |
| F14 | Perplexity "improved" after a tokenizer change | Lower per-token PPL, same or worse quality | Per-token metrics aren't comparable across tokenizers | Compare bits per byte or per character | Eval harness reports tokenizer-free metrics |
| F15 | RLHF policy exploits the reward model | Reward up, human ratings down; KL to the reference high | β too small (§1.18) | Raise β; fix the reward model; early-stop on KL | Track KL and human spot-checks alongside reward |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Our jailbreak classifier is 99% accurate. Why is the trust-and-safety team furious?"</b></summary>

**Initial Prompt.** TPR 0.99 and FPR 0.01 on the eval set. In production it blocks thousands of legitimate users a day.

**L5 Answer.** "The model is overfitting. Collect more training data and retrain."

**Why L5 Fails in Production.** The model performs exactly as measured. Accuracy on a 50/50 eval set says nothing about precision at the deployment base rate. Retraining doesn't change the base rate, so the problem comes back.

**L7 Principal Defense.** "Bayes: precision = TPR·π / (TPR·π + FPR·(1 − π)). At 0.1% attack prevalence, that's 0.09, so 91% of blocks are false, about 9,990 false blocks per million requests. The fix is structural. (1) Report precision at production prevalence. (2) Derive the threshold from costs: with C_FP = 1 and C_FN = 50, t* ≈ 0.02 on *calibrated*, prior-corrected scores, not 0.5. (3) Add a second, more precise stage for flagged traffic, and measure the *joint* FPR on held-out benign traffic, because the stages' errors correlate (we measured 0.373% vs the naive 0.1%). (4) Route uncertain cases to a soft action (step-up verification, human review) instead of a hard block."

**Bar-Raiser Follow-ups.**
- *"How do you set C_FN?"* With the product and security owners, in money or harm-equivalents. The math only needs the ratio, but someone must own it.
- *"Can you get precision without a second stage?"* Only by lowering FPR, i.e. raising the threshold, at the cost of recall. The odds form shows you need LR⁺ ≈ 1,000 (e.g., FPR 0.001) to reach ~50% precision at 0.1% prevalence.

</details>

<details><summary><b>Q2 · "Derive the threshold at which we should block."</b></summary>

**Initial Prompt.** A calibrated score s = P(attack | x) and a product team asking for "the right cut-off".

**L5 Answer.** "0.5. Or tune for the best F1."

**Why L5 Fails in Production.** 0.5 is the cost-optimal threshold only when C_FP = C_FN. F1 ignores costs and true negatives entirely. Both leave the business trade-off implicit.

**L7 Principal Defense.** "Block when the expected cost of blocking is lower than that of allowing: (1 − s)·C_FP < s·C_FN ⇔ s > C_FP/(C_FP + C_FN). With 1 : 50, t* = 0.0196. Brute force on 400k calibrated scores gives 0.0229, and the cost at t* is 0.521 vs 2.340 at 0.5. Two preconditions: calibrated scores (temperature or Platt scaling on a held-out split) and the production prior (prior correction if trained on balanced data). The deliverable is the threshold *and* the cost table, so the business can change the ratio and the threshold follows."

**Bar-Raiser Follow-ups.**
- *"What if the costs vary per request?"* Then the threshold varies per request: t*(x) = C_FP(x)/(C_FP(x) + C_FN(x)). That's common with user tiers or action severity.
- *"And with three actions (allow, review, block)?"* Two thresholds from the three-way cost comparison. Review is optimal in the middle band when its cost is below both error costs weighted by s.

</details>

<details><summary><b>Q3 · "Explain temperature in LLM sampling precisely. What does T = 0 actually guarantee?"</b></summary>

**Initial Prompt.** A product needs reproducible outputs for audit.

**L5 Answer.** "Temperature controls randomness. Set it to 0 and the output is deterministic."

**Why L5 Fails in Production.** T → 0 is greedy argmax, but argmax over logits that themselves vary run to run. The kernels aren't batch-invariant, so outputs differ under load. On current Claude models, temperature can't even be set: API version 2026-10-21 rejects the parameter.

**L7 Principal Defense.** "Temperature divides logits before the softmax. Entropy is monotone in T, with dH/dT = Var_p(z)/T³, from greedy at T → 0 to uniform at T → ∞. T = 0 guarantees argmax of *the logits computed in this run*. Floating-point sums aren't associative, and GPU reduction order varies with batch size, so logits jitter in the last bits. Any near-tie then flips and the continuation diverges. Thinking Machines measured 80 distinct outputs in 1,000 temperature-0 runs on Qwen3-235B, all identical once they used batch-invariant kernels (at roughly 1.6–2× the latency). For audit reproducibility I'd store the produced output and its inputs, not re-generate. For consistency I'd use structured outputs, validators and caching. Where I serve open-weight models and truly need bitwise reproducibility, I'd enable batch-invariant kernels and pay the latency."

**Bar-Raiser Follow-ups.**
- *"Top-p vs min-p at high temperature?"* Top-p's kept set explodes (46 → 33,510 tokens from T = 0.7 to 1.5 on our Zipf vocabulary), while min-p scales with confidence (13 → 97). Min-p keeps high-T sampling coherent.
- *"Does filter order matter?"* Yes. HF applies temperature → top-k → top-p → min-p, and reversing temperature and top-p keeps 7,664 instead of 33,510 tokens in our example.

</details>

<details><summary><b>Q4 · "Our classifier's confidence scores are useless for routing. Fix them without retraining."</b></summary>

**Initial Prompt.** A fine-tuned BERT intent model says 0.99 on everything, including its mistakes.

**L5 Answer.** "Retrain with label smoothing, or use a different model."

**Why L5 Fails in Production.** Retraining is expensive and may not fix calibration. Label smoothing changes calibration unpredictably and hurts any later distillation (Müller et al.). There is a one-parameter post-hoc fix that can't hurt accuracy.

**L7 Principal Defense.** "Temperature scaling: fit one scalar T on a held-out split by minimizing NLL, then serve softmax(z/T). Argmax is invariant, so accuracy can't change, and only the confidence moves. On our overconfident model, T = 2.01 cut ECE from 0.182 to 0.009 at identical accuracy (0.756). With calibrated confidence, the router can escalate below t and know the outcome in advance: at t = 0.7, it answers 67.4% locally at 0.853 accuracy, matching the mean confidence of 0.850. If calibration differs by class or by segment, step up to vector scaling or per-segment temperatures, validated on held-out data."

**Bar-Raiser Follow-ups.**
- *"Why NLL and not ECE as the fitting objective?"* NLL is a proper scoring rule, smooth and unbinned. ECE depends on binning and is a diagnostic, not an objective.
- *"How often do you refit T?"* Whenever the model or the traffic mix changes. Monitor ECE on a labelled production sample, since drift breaks calibration before it breaks accuracy.

</details>

<details><summary><b>Q5 · "We use an LLM-as-judge for evals. Can we trust its scores?"</b></summary>

**Initial Prompt.** The judge rates 56% of answers as acceptable. Leadership tracks that number weekly.

**L5 Answer.** "Yes, LLM judges correlate well with humans. Use a stronger judge model if worried."

**Why L5 Fails in Production.** Correlation isn't calibration. A judge can rank answers well and still be biased toward "yes", so the weekly number is inflated by a constant and drifts when the judge model or prompt changes. A stronger judge doesn't remove the bias by itself.

**L7 Principal Defense.** "Treat the judge as a classifier and calibrate it against humans. Take P(yes) from log-probs where available (or from repeated sampling), get ~500 human labels, and fit Platt scaling, σ(a·z + b). Temperature alone can't fix an intercept: in our test the raw judge said yes 56.1% of the time vs a human rate of 38.7%, temperature left it at 56.0%, and Platt brought it to 38.4% (NLL 0.652 → 0.458). Then report the calibrated rate with a confidence interval, and re-run the human-agreement check whenever the judge's model or prompt changes. Two humans' agreement on the same items sets the ceiling the judge is compared against (§4.3)."

**Bar-Raiser Follow-ups.**
- *"No log-probs available?"* Sample the judge k times and use the yes-fraction as the score, then calibrate that. Or ask for a structured 1–5 score and calibrate the mapping from score to human pass rate.
- *"Position or verbosity bias?"* Separate audits (swap order, length-controlled pairs), covered in Folder 06.

</details>

<details><summary><b>Q6 · "Explain cross-entropy loss, perplexity and KL as one idea."</b></summary>

**Initial Prompt.** The interviewer wants the connections, not three definitions.

**L5 Answer.** "Cross-entropy measures the difference between predicted and true distributions, perplexity is its exponential, and KL is another divergence."

**Why L5 Fails in Production.** It misses the identity that makes them the same objective, and the asymmetry that decides which one you use in distillation or RLHF.

**L7 Principal Defense.** "H(p, q) = H(p) + KL(p‖q). With p the data distribution, H(p) is fixed, so minimizing cross-entropy *is* minimizing forward KL to the data, which *is* maximum likelihood (Gibbs: KL ≥ 0, zero iff q = p). Perplexity = exp(cross-entropy in nats), the effective branching factor: loss 2.0 is perplexity 7.39, or 2.885 bits per token, which is also the model's compression rate on that text. Forward KL is mode-covering, which is why SFT models hedge. Reverse KL is mode-seeking, which is what on-policy distillation and the RLHF KL leash use. Our one-Gaussian fit shows it: forward picks μ = 0, σ = 3.1 across both modes, reverse picks μ = 3, σ = 0.7 on one."

**Bar-Raiser Follow-ups.**
- *"Compare perplexities of two models?"* Only with the same tokenizer and text. Otherwise use bits per byte.
- *"Why is KL(p‖q) dangerous when q has zeros?"* It's infinite where q = 0 and p > 0. We measured 8.8 nats at q = 1e-8 and climbing. Smooth, or use JS (bounded by ln 2) for monitoring.

</details>

<details><summary><b>Q7 · "How would you detect hallucinations in our RAG answers?"</b></summary>

**Initial Prompt.** A customer-facing QA bot occasionally invents policy details.

**L5 Answer.** "Check token log-probabilities and flag low-confidence answers."

**Why L5 Fails in Production.** Token log-probs mix lexical uncertainty (phrasing) with semantic uncertainty (facts). They may not be available from the provider at all (Claude returns none; some reasoning models reject them). And they miss systematic errors the model is confident about.

**L7 Principal Defense.** "Layered. (1) **Grounding check:** does each claim entail from the retrieved passages? An NLI model or an LLM judge, calibrated against human labels, catches unsupported claims regardless of confidence. (2) **Semantic entropy** on high-stakes or flagged traffic: sample about 10 answers, cluster them by bidirectional entailment, and compute entropy over meanings. In our simulation it detects wrong answers at AUROC 0.896 vs 0.843 for string-level entropy, and abstaining above 0.9 cuts errors on answered questions from 28.3% to 0.6% at 55% coverage. (3) Token log-probs as a cheap extra signal *where available*. Semantic entropy targets confabulation, not systematic error. Grounding checks cover the latter, and the error-analysis spreadsheet tells you which one dominates."

**Bar-Raiser Follow-ups.**
- *"Cost?"* About 10× generation plus ~15 entailment checks per question with greedy clustering. Gate it by a cheap first-pass signal so it runs on a few percent of traffic.
- *"What breaks semantic entropy?"* Over-merging clusters (AUROC 0.896 → 0.883 when we merged distinct dates), long multi-claim answers (split into claims first), and confidently wrong models.

</details>

<details><summary><b>Q8 · "Why does distillation use a temperature, and why multiply by T²?"</b></summary>

**Initial Prompt.** You're distilling a large intent classifier into a small one.

**L5 Answer.** "Temperature softens the teacher's outputs so the student learns more. T² is a normalization."

**Why L5 Fails in Production.** "A normalization" doesn't say what breaks without it. Without T², changing T silently reweights the soft and hard losses, so the T sweep is confounded.

**L7 Principal Defense.** "At T = 1 the teacher's distribution is nearly one-hot, and the relative probabilities of wrong classes (the dark knowledge) are invisible. Dividing logits by T > 1 exposes them. The soft-target gradient with respect to the student logits is (p_s(T) − p_t(T))/T, and for large T, p_s − p_t ≈ (z_s − z_t)/(K·T), so the gradient shrinks as 1/T². Multiplying the soft loss by T² keeps its weight constant as you sweep T. We measured ‖grad‖·T² flattening to a constant (0.39 → 0.38 at T = 8 → 16). The divergence is forward KL(teacher ‖ student), mode-covering, so the student learns the full distribution."

**Bar-Raiser Follow-ups.**
- *"Label smoothing on the teacher?"* It can hurt distillation by erasing exactly the inter-class information the student needs (Müller et al.).
- *"Distilling an LLM's behaviour instead?"* Sequence-level distillation trains on teacher generations. On-policy distillation has the student sample and the teacher score per token with reverse KL.

</details>

<details><summary><b>Q9 · "Softmax or sigmoid for our content-policy classifier?"</b></summary>

**Initial Prompt.** Labels: PII, toxic, jailbreak, benign.

**L5 Answer.** "Softmax. It's a classification problem with four classes."

**Why L5 Fails in Production.** Policy labels aren't mutually exclusive. With softmax, a prompt that is both PII-leaking and toxic splits its probability mass and can pass every threshold.

**L7 Principal Defense.** "One sigmoid per violation label, each trained with binary cross-entropy, each with its own calibrated, cost-derived threshold, plus an implicit 'benign' when none fire. In our example, logits of 2.1 for both PII and toxic give softmax 0.49 / 0.49, so nothing flags at 0.5. Sigmoids give 0.89 / 0.89 and flag both. Softmax is right for routing to exactly one intent. Mixing the two (softmax for intents, sigmoids for policies) on one shared embedding is the usual design."

**Bar-Raiser Follow-ups.**
- *"Thresholds per label?"* Yes, because the costs differ per label (§1.3), and so do the base rates (§1.4).
- *"Label correlations?"* Independent sigmoids don't model them. If they matter, add pairwise features or a small second-stage model, measured on the eval.

</details>

<details><summary><b>Q10 · "What does the KL term in RLHF actually do? What happens if β is too small?"</b></summary>

**Initial Prompt.** Your RLHF run's reward keeps rising while human ratings fall.

**L5 Answer.** "The KL penalty prevents the model from changing too much. Increase it if training is unstable."

**Why L5 Fails in Production.** It describes the symptom, not the mechanism. It also misses the diagnosis: rising reward with falling human ratings means the policy is exploiting the reward model, and the KL coefficient sets how far it's allowed to go.

**L7 Principal Defense.** "The objective E_π[r] − β·KL(π‖π_ref) has the closed-form optimum π* ∝ π_ref·exp(r/β). We verified it against gradient ascent to 3 decimals. β is the leash. At β = 0.1, all mass goes to the highest-reward response (E[r] 2.998, KL 2.985). At β = 5, the policy barely moves (KL 0.015). Reward up with human ratings down is reward hacking: the policy found a region where the reward model is wrong, and a small β let it go there. Fixes: raise β, fix the reward model on the exploited region (error analysis on high-reward, low-human-rating samples), and early-stop on KL. DPO optimizes the same objective directly from preference pairs, via r = β·log(π/π_ref) + const."

**Bar-Raiser Follow-ups.**
- *"Why is it reverse KL (policy ‖ reference)?"* It's an expectation under the policy's own samples, so it's computable on-policy, and it's mode-seeking: the policy may drop modes of the reference but is penalized for inventing mass where the reference has none.

</details>

<details><summary><b>Q11 · "Our classifier was trained on balanced data. In production it flags 16% of traffic. What's going on?"</b></summary>

**Initial Prompt.** True attack rate ~1%.

**L5 Answer.** "Raise the threshold until the flag rate looks right."

**Why L5 Fails in Production.** Hand-tuning the threshold to hit a flag rate isn't tied to costs and breaks when the prior moves again. The probabilities also stay wrong for every downstream consumer.

**L7 Principal Defense.** "Label shift. The posterior is right for a 50/50 prior and wrong for 1%. If p(x | y) didn't change, Bayes gives an exact correction: multiply the class odds by (π/π_t)/((1 − π)/(1 − π_t)) and renormalize. In our simulation that moved the mean probability from 0.230 to 0.0100 (true rate 0.0101), cut log-loss from 0.355 to 0.037, cut flags from 16.5% to 0.15%, and raised precision at 0.5 from 0.05 to 0.68. Then apply the cost-derived threshold on the corrected scores. Monitor the mean predicted probability against the observed base rate. A gap means the prior moved, or p(x | y) did, and the latter needs retraining."

**Bar-Raiser Follow-ups.**
- *"How do you know π in production?"* Estimate it from a labelled random sample, or with EM on the classifier's outputs (Saerens et al.'s method), cross-checked with periodic labelling.

</details>

---

## 7. Invariants Checklist

- [ ] Precision, alert volume and cost are reported at **production prevalence** (or reweighted). Recall and FPR are reported as model properties.
- [ ] Multi-stage guardrails have their **joint** FPR measured on held-out benign traffic. Marginals are never multiplied.
- [ ] Every decision threshold is derived from written-down costs, t* = C_FP/(C_FP + C_FN), applied to calibrated, prior-corrected scores.
- [ ] Classifiers trained on re-balanced data are prior-corrected before thresholding. The mean predicted p is monitored against the observed base rate.
- [ ] Every probability consumed downstream is calibrated (temperature or Platt) on a held-out split, with ECE and a reliability table in the model card.
- [ ] LLM judges are calibrated against human labels (Platt), with human-human agreement recorded as the ceiling.
- [ ] Multi-label policies use independent sigmoids with per-label thresholds. Softmax is used only for mutually exclusive classes.
- [ ] Softmax implementations subtract the max (or use log-sum-exp). fp16 paths keep the running max in fp32.
- [ ] Sampling configurations document the filter order. Cross-stack ports are tested.
- [ ] No design depends on temperature-0 determinism. Audit trails store outputs, not regeneration recipes.
- [ ] Claude request builders send no `temperature` / `top_p` / `top_k` under API version 2026-10-21.
- [ ] Hallucination detection doesn't depend on vendor log-probs unless the availability matrix confirms them for the exact model.
- [ ] Distillation multiplies the soft loss by T². Teacher and student are softened with the same T.
- [ ] Perplexity is compared only under the same tokenizer. Otherwise bits per byte.
- [ ] RLHF runs track KL to the reference and human spot-checks alongside reward.

---

## 8. References

1. C. Guo, G. Pleiss, Y. Sun, K. Weinberger, *On Calibration of Modern Neural Networks*, ICML 2017. https://arxiv.org/abs/1706.04599
2. J. Platt, *Probabilistic Outputs for Support Vector Machines and Comparisons to Regularized Likelihood Methods*, 1999 (Platt scaling).
3. G. Hinton, O. Vinyals, J. Dean, *Distilling the Knowledge in a Neural Network*, 2015. https://arxiv.org/abs/1503.02531
4. S. Farquhar, J. Kossen, L. Kuhn, Y. Gal, *Detecting hallucinations in large language models using semantic entropy*, Nature 630, 625–630, 2024-06-19. DOI 10.1038/s41586-024-07421-0. Blog: https://oatml.cs.ox.ac.uk/blog/2024/06/19/detecting_hallucinations_2024.html
5. L. Kuhn, Y. Gal, S. Farquhar, *Semantic Uncertainty: Linguistic Invariances for Uncertainty Estimation in Natural Language Generation*, ICLR 2023. https://arxiv.org/abs/2302.09664
6. H. He and Thinking Machines Lab, *Defeating Nondeterminism in LLM Inference*, 2025-09-10. https://thinkingmachines.ai/blog/defeating-nondeterminism-in-llm-inference/
7. Hugging Face `transformers`, `generation/utils.py` (`_get_logits_processor`: temperature → top-k → top-p → min-p). https://github.com/huggingface/transformers/blob/main/src/transformers/generation/utils.py
8. A. Holtzman et al., *The Curious Case of Neural Text Degeneration* (nucleus sampling), ICLR 2020. https://arxiv.org/abs/1904.09751
9. M. Nguyen et al., *Turning Up the Heat: Min-p Sampling for Creative and Coherent LLM Outputs*, 2024. https://arxiv.org/abs/2407.01082
10. Anthropic, *API versions* (version 2026-10-21 returns 400 for Messages requests that send `temperature`, `top_p` or `top_k`; Claude 4.7 and later accept only default sampling values). https://platform.claude.com/docs/en/api/versioning
11. A. van den Oord, Y. Li, O. Vinyals, *Representation Learning with Contrastive Predictive Coding* (InfoNCE bound), 2018. https://arxiv.org/abs/1807.03748
12. R. Müller, S. Kornblith, G. Hinton, *When Does Label Smoothing Help?*, NeurIPS 2019. https://arxiv.org/abs/1906.02629
13. T.-Y. Lin et al., *Focal Loss for Dense Object Detection*, ICCV 2017. https://arxiv.org/abs/1708.02002
14. R. Rafailov et al., *Direct Preference Optimization: Your Language Model is Secretly a Reward Model*, NeurIPS 2023. https://arxiv.org/abs/2305.18290
15. L. Ouyang et al., *Training language models to follow instructions with human feedback* (InstructGPT, KL-penalized RLHF), 2022. https://arxiv.org/abs/2203.02155
16. M. Xiong et al., *Can LLMs Express Their Uncertainty? An Empirical Evaluation of Confidence Elicitation in LLMs*, ICLR 2024. https://arxiv.org/abs/2306.13063
17. M. Saerens, P. Latinne, C. Decaestecker, *Adjusting the Outputs of a Classifier to New a Priori Probabilities*, Neural Computation 14(1), 2002. DOI 10.1162/089976602753284446.
18. T. Gao, X. Yao, D. Chen, *SimCSE: Simple Contrastive Learning of Sentence Embeddings* (τ = 0.05), 2021. https://arxiv.org/abs/2104.08821
19. A. Radford et al., *Learning Transferable Visual Models From Natural Language Supervision* (CLIP, learned temperature), 2021. https://arxiv.org/abs/2103.00020
20. A. Ng, *Improve Agentic Performance with Evals and Error Analysis, Part 1*, The Batch, 2025-10-15. https://www.deeplearning.ai/the-batch/improve-agentic-performance-with-evals-and-error-analysis-part-1/
21. A. Ng, *Machine Learning Yearning* (dev/test sets from the distribution you expect; human-level performance as a Bayes-error proxy). https://www.deeplearning.ai/resources/
