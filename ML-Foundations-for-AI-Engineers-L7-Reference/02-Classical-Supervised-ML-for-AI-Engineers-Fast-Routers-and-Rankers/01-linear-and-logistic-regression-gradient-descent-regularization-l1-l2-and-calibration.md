# 02.1 · Linear & Logistic Regression: Gradient Descent, L1/L2 Regularization & Calibration

> **Folder 02 · Classical Supervised ML for AI Engineers: Fast Routers & Rankers**
> **Measured on:** scikit-learn 1.9.1, NumPy 2.5.4, PyTorch 2.14.1 (CPU), transformers 5.22.0, CPython 3.14.5, Intel i5-11260H, Windows 11.
> **Real data:** CLINC150 (Larson et al., 2019: 150 intents × 100 training utterances, plus out-of-scope queries) encoded with `sentence-transformers/all-MiniLM-L6-v2` (22.7M parameters, 384-d). Both were downloaded once into an isolated directory and read only by `python -I` listings.
> **Design sources:** the scikit-learn user guide (linear models, probability calibration), Niculescu-Mizil & Caruana (2005), the all-MiniLM-L6-v2 model card. Full list in §8.

---

## 0. Orientation: The Head You Will Ship More Than Any Other

Here's the Andrew Ng-style summary: **a logistic-regression head on top of frozen embeddings is the "hello world" of production AI engineering, and also its workhorse.** The encoder turns text into a point on the sphere (Folder 01). The head draws hyperplanes between classes. Training takes seconds, serving takes microseconds, the probabilities can be calibrated, and the weights fit in a 231 KB array. In this file's measurements, one such head routes 150 intents at **0.955** test accuracy, and its scoring step costs **15.7 µs** per query in NumPy.

Linear models are also the cleanest place to learn three ideas that carry into every later folder:

- **Optimization:** gradient descent, the condition number, Newton's method.
- **Regularization:** L2 as a Gaussian prior, L1 as feature selection, and the fact that some problems have no answer without it.
- **Calibration:** when a model's probability is a probability.

### The backend-engineer bridge

| You already know | ML equivalent | Why it maps |
|---|---|---|
| A config-driven rule engine: `if score > t then route` | **A linear head:** `argmax(W·x + b)` | Same shape, but W is learned from data instead of hand-written |
| Query-planner statistics drive index choice | **Condition number** drives optimizer convergence | Badly scaled inputs make a correct algorithm thousands of times slower (measured: 12 vs 120,006 steps) |
| Capacity planning with headroom | **Regularization strength C** | Too little capacity underfits (bias), too much memorizes noise (variance) |
| Calibrating a load-test model against production | **Probability calibration** | A score is useless for thresholds until it means what it says |
| Shipping a config file, not a binary | **Shipping `W.npy` + `b.npy`, not a pickled estimator** | A 231 KB array is portable, auditable and has no deserialization risk |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 Frozen-embedding feature pipeline (pooling, normalization, batching, latency) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Linear regression and the normal equations | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.3 Gradient descent and the condition number | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Ridge (L2) as a Gaussian prior; Lasso (L1) as feature selection | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Logistic and softmax regression: loss, gradient, Hessian, Newton | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Separable data: why regularization is not optional | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Calibration of classical models | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Bias and variance through C and learning curves | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 Solver choice in scikit-learn | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 GLM theory and IRLS convergence proofs | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 The frozen-embedding feature pipeline `[MUST-KNOW: Core AI Engineer Edge]`

Every head in Folders 02–03 sits on the same pipeline (listing §3.1):

```text
text ─► WordPiece tokenizer ─► MiniLM (6 layers, 384-d, 22.7M params) ─► token states (n_tokens × 384)
     ─► mean pooling over the attention mask ─► L2 normalize ─► x ∈ S³⁸³ (unit sphere)
```

Three details decide quality and cost:

1. **Pooling must respect the mask.** Padding positions carry hidden states too. Average them in and short texts in a long batch get diluted. The listing divides the masked sum by the mask count. The model's own `1_Pooling/config.json` says `pooling_mode_mean_tokens: true`, and `modules.json` ends in `Normalize`, so the vectors are unit length (norms 1.000000 ± 1e-6). From here on, dot product equals cosine (01.1 §1.2).
2. **Batch by length.** In a padded batch, every sequence costs as much as the longest. For 4,096 CLINC utterances in batches of 128, unsorted batching computes **85,632** token slots for 44,781 real tokens (1.91×). Sorting by length first cuts that to **61,952** (1.38×), about 28% less encoder compute for free.
3. **Single-query latency is the router's latency.** Eager PyTorch on this laptop CPU, including tokenization and pooling: p50 **9.43 ms** at 1 thread and **6.10 ms** at 4 threads. 02.3 brings that to about 2 ms with ONNX Runtime and int8. The head itself is three orders of magnitude cheaper (§3.3).

### 1.2 Linear regression and the normal equations `[GOOD-TO-KNOW: Architectural Literacy]`

Minimize squared error `L(w) = ½‖Xw − y‖²`. The gradient is `Xᵀ(Xw − y)`. Setting it to zero gives the **normal equations**:

```text
XᵀX w = Xᵀy   ⇒   w* = (XᵀX)⁻¹Xᵀy          (when XᵀX is invertible)
```

Geometrically, Xw* is the **orthogonal projection** of y onto the column space of X, and the residual is perpendicular to every feature:

```text
                  y
                  ●
                  │\
         residual │  \      residual ⟂ span(X):  Xᵀ(y − Xw*) = 0
                  │    \
   ───────────────●──────────────  span(columns of X)
                Xw*
```

The listing confirms closed form = scikit-learn to 4.7e-15. AI engineers meet OLS in fitting scaling-law curves, CUPED variance reduction in A/B tests (Folder 06), and every "regress metric on covariates" analysis. In practice solve with a QR or Cholesky factorization (what `lstsq` does), never by forming an explicit inverse.

### 1.3 Gradient descent and the condition number `[MUST-KNOW: Core AI Engineer Edge]`

On a quadratic loss with Hessian H = XᵀX/n, gradient descent with step 1/L (L = largest eigenvalue) shrinks the error along each eigendirection by a factor (1 − λᵢ/L) per step. The slowest direction has λ_min, so

```text
error_t ≈ (1 − 1/κ)^t · error_0,     κ = λ_max / λ_min    (the condition number)
steps to reach ε ≈ κ · ln(1/ε)
```

```text
   well-conditioned (κ ≈ 1)            ill-conditioned (κ ≫ 1)
        contours ≈ circles                 contours = long thin ellipses
            ╭───╮                     ╭─────────────────────────────╮
           │  ●  │  → straight         ╰─────────────────────────────╯
            ╰───╯     to the min        GD zig-zags across the valley, crawls along it
```

Measured in §3.2 on the same 2,000 × 20 problem:

```text
features                      cond(X^T X)  GD steps to 1e-6
standardized                          1.5                12
raw: scales 1..100                10274.0           120,006
raw: scales 1..1000             1025140.1           200,000 (hit the 200,000 cap)
```

Same data, same minimum, 10,000× more work. **Standardize features before any gradient-based fit.** For embedding heads this is mostly free, since unit-norm MiniLM vectors are already well scaled. For *mixed* features (an embedding concatenated with a raw token count, or a dollar amount), skipping `StandardScaler` is the classic cause of "lbfgs failed to converge". Second-order methods (Newton, L-BFGS) are far less sensitive because they rescale by curvature, which is part of why scikit-learn defaults to lbfgs.

### 1.4 Ridge (L2) as a Gaussian prior; Lasso (L1) as feature selection `[MUST-KNOW: Core AI Engineer Edge]`

**Ridge.** Minimize `½‖Xw − y‖² + ½λ‖w‖²`, which gives `w* = (XᵀX + λI)⁻¹Xᵀy`. Adding λI does two things:

- It makes the matrix invertible, with condition number at most (λ_max + λ)/λ.
- It shrinks w toward 0, most along low-variance directions (in the SVD basis, each component is multiplied by σᵢ²/(σᵢ² + λ)).

**Why it's a prior.** With Gaussian noise y ~ N(Xw, σ²) and prior w ~ N(0, (σ²/λ)I), the log-posterior is

```text
log p(w | y) = −(1/2σ²)‖Xw − y‖² − (λ/2σ²)‖w‖² + const     ⇒   MAP estimate = ridge
```

So λ is a statement of belief: "weights are small unless the data insists." The listing's shrinkage path takes ‖w‖ from 4.0879 at λ = 0 to 2.7405 at λ = 1000 (true ‖w‖ = 4.1026).

**Lasso.** Replace ‖w‖² with ‖w‖₁. That is the MAP estimate under a Laplace prior, which has a sharp peak at 0. The constraint region becomes a diamond whose corners lie on the axes, so the optimum often lands exactly on a corner, where some weights are *exactly* zero:

```text
          L2 constraint (circle)              L1 constraint (diamond)
                ╭───╮                                ◆
              ╭─┴───┴─╮  loss contours             ╱   ╲    contours usually
              │   ●   │← touch at a point         ◆  ●  ◆   first touch a CORNER
              ╰───────╯  with both w₁, w₂ ≠ 0      ╲   ╱    → one coordinate = 0
                                                     ◆
```

Measured on 200 features with 10 informative ones:

```text
  alpha L1 nonzero true found L2 nonzero
   0.01        120         10        200
   0.20         10         10        200
```

At α = 0.2, the Lasso keeps exactly the 10 true features. Ridge keeps all 200 with small weights. For AI engineering, L1 matters when features are *engineered* and costly to compute online (hand-built guardrail signals, meta-features). It tells you which ones to stop computing. On dense embeddings, L2 is the default: embedding coordinates aren't individually meaningful (01.1 §1.1), so sparsity in them buys nothing.

### 1.5 Logistic and softmax regression: loss, gradient, Hessian, Newton `[MUST-KNOW: Core AI Engineer Edge]`

**Model.** `P(y = 1 | x) = σ(wᵀx + b)`, with σ(z) = 1/(1 + e⁻ᶻ). Equivalently, the **log-odds are linear**: `log(p/(1 − p)) = wᵀx + b`. Each weight is an additive contribution to the log-likelihood ratio, the odds form of Bayes from 01.3 §1.2. That's why the coefficients of a logistic guardrail can be read as "evidence per feature".

**Loss** (negative log-likelihood = cross-entropy), its gradient, and its Hessian:

```text
L(w) = −Σᵢ [ yᵢ log pᵢ + (1 − yᵢ) log(1 − pᵢ) ] + ½λ‖w‖²
∇L   = Xᵀ(p − y) + λw                                  (the p − y gradient again: 01.3 §1.11)
∇²L  = Xᵀ S X + λI,    S = diag(pᵢ(1 − pᵢ))
```

The Hessian is positive semi-definite (S ≥ 0), positive definite with λ > 0, so **the loss is convex**: one global minimum, and any solver that converges finds the same weights. The listing's Newton iteration, `w ← w − H⁻¹∇L` (also called IRLS, iteratively reweighted least squares), converges in **8** iterations, where gradient descent takes **452**. Its solution matches scikit-learn's lbfgs to **3.4e-09**.

**Multiclass: softmax regression.** K classes, a weight matrix W (K × d), and `P(y = k | x) = softmax(Wx + b)ₖ`. The gradient for row k is `Σᵢ (pᵢₖ − yᵢₖ) xᵢ`. The 150-intent CLINC head is exactly this: a 150 × 384 matrix plus 150 biases, 57,750 parameters. Geometrically, it learns **discriminative** hyperplanes. The nearest-centroid router of 01.1 §1.11 is the special case with W = class means and b = 0, and learning W directly is why LR beats centroids on in-scope accuracy (0.955 vs 0.917 in 02.3).

### 1.6 Separable data: why regularization is not optional `[MUST-KNOW: Core AI Engineer Edge]`

If a hyperplane separates the classes perfectly, scaling w up always lowers the loss: every margin grows, every pᵢ → yᵢ. The unregularized maximum-likelihood estimate **does not exist** (it's at infinity). Optimizers then run until a tolerance stops them, and you ship arbitrarily overconfident probabilities. §3.2 measures it on separable 2-D data:

```text
       C     ||w||          max p  mean |p - 0.5|
   1e-01      1.98   0.9933140549          0.2845
   1e+00      4.91   0.9999962789          0.4026
   1e+06    251.03   1.0000000000          0.4999
```

As C grows (less regularization), ‖w‖ explodes and every prediction saturates to 0 or 1. **High-dimensional embedding heads are almost always separable on their training set:** 15,000 points in 384 dims across 150 classes, with train accuracy 0.9993 at C = 100. So the regularizer isn't a tuning nicety. It's what makes the probabilities finite and meaningful. scikit-learn's `C` is the *inverse* regularization strength (C = 1/λ), and it penalizes the weights but not the intercept.

### 1.7 Calibration of classical models `[MUST-KNOW: Core AI Engineer Edge]`

Logistic regression minimizes log-loss, a **proper scoring rule**, so on data like its training data its probabilities tend to be reasonable. But "reasonable" depends on the regularizer. Niculescu-Mizil & Caruana (2005) showed that other model families distort probabilities in characteristic ways:

- Naive Bayes pushes them toward 0 and 1.
- Max-margin methods (SVMs) produce scores that aren't probabilities at all.
- Boosted trees push them away from the extremes.

The CLINC measurement (§3.3, in-scope test set):

```text
head                                   acc     NLL     ECE mean conf
LogisticRegression C=10.0           0.9547  0.2278  0.0762    0.8786
LinearSVC + sigmoid (3-fold)        0.9478  0.2651  0.0954    0.8537
LinearSVC + isotonic (3-fold)       0.9436  0.5189  0.0333    0.9134
GaussianNB                          0.9142  1.7778  0.0830    0.9973
LR + temperature T=0.63             0.9547  0.1645  0.0062    0.9535
```

Four lessons:

1. **The LR head is *under*-confident here.** Mean confidence 0.879 at 95.5% accuracy. Regularization (C = 10) shrinks the logits. The fitted temperature is **T = 0.63 < 1**, which *sharpens* the distribution: ECE drops 12× (0.0762 → 0.0062) and NLL from 0.228 to 0.165, with accuracy unchanged. Temperature scaling (01.3 §1.13) corrects miscalibration in either direction.
2. **Naive Bayes is overconfident.** Mean confidence 0.997 at 91.4% accuracy, NLL 1.78. Its "independent features" assumption counts correlated embedding dimensions as separate evidence.
3. **SVM scores need a calibrator.** `CalibratedClassifierCV` fits Platt (sigmoid) or isotonic regression on held-out folds. Isotonic has the lowest ECE here (0.033) but a much worse NLL (0.519): it's a step function that assigns near-zero probability to some correct answers. Low ECE and high NLL together mean "good on average, terrible on some examples".
4. **ECE alone can mislead.** Report NLL (or Brier score) next to it.

### 1.8 Bias and variance through C and learning curves `[MUST-KNOW: Core AI Engineer Edge]`

```text
     C train acc  val acc  val NLL  ||W||_F
   0.1    0.9401   0.9143   2.2204     59.9      ← high bias: underfits even the training set
   1.0    0.9805   0.9513   0.5454    134.9
  10.0    0.9975   0.9600   0.2296    216.7      ← best validation accuracy
 100.0    0.9993   0.9560   0.1769    328.4      ← variance creeping in: train ↑, val ↓
```

Ng's diagnostic reads this directly. At C = 0.1 the training accuracy itself is low (0.940), which is avoidable bias. At C = 100 the train–val gap widens (0.9993 vs 0.9560), which is variance. Note that **validation NLL keeps improving to C = 100 while accuracy peaks at C = 10.** If downstream consumers use the probabilities (thresholds, cascades), select C on NLL, or select on accuracy and then calibrate with temperature. Don't assume the two criteria agree.

**The learning curve answers "should we collect more labels?"**:

```text
per intent train rows  val acc
         5        750   0.8657
        10      1,500   0.9010
        25      3,750   0.9347
        50      7,500   0.9517
       100     15,000   0.9597
```

Going from 50 to 100 examples per intent buys 0.8 points. Going from 5 to 10 buys 3.5. The curve is flattening, so another 100 per intent would likely buy a fraction of a point. The next gains come from error analysis (02.3) and better representations (a fine-tuned encoder, Folder 04), not from more labels of the same kind.

### 1.9 Solver choice in scikit-learn `[GOOD-TO-KNOW: Architectural Literacy]`

| Solver | Method | Use it for |
|---|---|---|
| `lbfgs` (default) | Quasi-Newton, L2 only | Dense features, multiclass softmax: embedding heads |
| `newton-cholesky` | Exact Newton | Many samples, few features (n ≫ d), when you want exact convergence |
| `liblinear` | Coordinate descent / trust region | Small data, L1, one-vs-rest |
| `saga` | Stochastic average gradient | Large sparse data (TF-IDF), L1/elastic-net |

All of them minimize the same convex objective, so they reach the same answer, at different speeds and with different memory footprints. A "failed to converge" warning on embeddings usually means unscaled extra features or too few iterations, and very rarely that lbfgs itself is a bad choice.

### 1.10 GLM theory and IRLS convergence proofs `[SKIP: Academic/Research Only]`

Logistic regression is a generalized linear model with a canonical link. IRLS is Newton's method on its likelihood, with quadratic convergence near the optimum. The exponential-family theory unifies Poisson, gamma and binomial regressions. Production only needs the facts above: convexity, the p − y gradient, and why regularization is required.

---

## 2. Where It Beats an LLM in Production

| Task | Linear head on frozen embeddings | Prompted LLM |
|---|---|---|
| Intent routing (CLINC150, 150 intents) | 0.955 test accuracy; head 15.7 µs in NumPy; encoder ~2 ms with ONNX int8 (02.3) | One generation call per request (01.1 §2: 113×–4,533× an embedding call) and no calibrated probability |
| Topic, language or sentiment triage | Same pattern; retrain in seconds when labels change | A prompt change per new class, re-validated by hand |
| Guardrail first stage | Calibrated P(violation) for the cost-optimal threshold (01.3 §1.3) | Verbal confidence, poorly calibrated |
| Feature for a downstream model | Probabilities and margins as meta-features (02.2) | Text that must be parsed |

The economics are lopsided because the head is tiny and the expensive part, the encoder, is *shared*. One embedding serves the router, the semantic cache, the guardrail head and retrieval (01.2 §2.2). Each extra head costs a 384-wide matrix-vector product.

When the LLM is the right tool: classes defined by reasoning ("is this request asking us to break policy, given the conversation?"), classes with no labelled data yet (zero-shot), and long inputs where one embedding averages away the signal.

---

## 3. Production Code Blueprint

### 3.1 The frozen-embedding pipeline (CLINC150 → MiniLM → cache)

```python
"""encode_clinc_minilm.py - the frozen-embedding feature pipeline used by Folders 02-03: CLINC150 -> all-MiniLM-L6-v2.

  1. Load CLINC150 (150 intents + out-of-scope queries) and the encoder from local, pinned snapshots.
  2. Mean-pool token states over the attention mask, then L2-normalize (the model's own pooling config).
  3. Length-bucketed batching: how much padding compute sorting by length saves.
  4. Single-query latency on CPU at 1 and 4 threads (the number that decides whether a router is "2 ms").
  5. Cache embeddings to KB_DATA/clinc_minilm.npz for every later listing.
Inputs: KB_DL (downloaded data, read-only), KB_DATA (outputs).
"""
import json
import os
import time

import numpy as np
import torch
from transformers import AutoModel, AutoTokenizer

DL, DATA = os.environ["KB_DL"], os.environ["KB_DATA"]
os.makedirs(DATA, exist_ok=True)
torch.manual_seed(0)

raw = json.load(open(os.path.join(DL, "clinc", "data_full.json"), encoding="utf-8"))
splits = {k: raw[k] for k in ("train", "val", "test", "oos_train", "oos_val", "oos_test")}
labels = sorted({lab for text, lab in raw["train"]})
lab_id = {l: i for i, l in enumerate(labels)}
print("CLINC150 split sizes: " + ", ".join(f"{k}={len(v)}" for k, v in splits.items()) + f"; {len(labels)} intents")

mdir = os.path.join(DL, "models", "minilm")
tok = AutoTokenizer.from_pretrained(mdir)
model = AutoModel.from_pretrained(mdir, use_safetensors=True).eval()
pool_cfg = json.load(open(os.path.join(mdir, "1_Pooling", "config.json")))
modules = [m["type"].rsplit(".", 1)[-1] for m in json.load(open(os.path.join(mdir, "modules.json")))]
print(f"encoder: {sum(p.numel() for p in model.parameters()):,} params, hidden {model.config.hidden_size}, "
      f"{model.config.num_hidden_layers} layers; pooling mean={pool_cfg['pooling_mode_mean_tokens']}; modules {modules}")


@torch.inference_mode()
def encode(texts, batch=128, sort=True):
    order = np.argsort([len(t) for t in texts]) if sort else np.arange(len(texts))
    out = np.zeros((len(texts), model.config.hidden_size), dtype=np.float32)
    real = padded = 0
    for i in range(0, len(texts), batch):
        idx = order[i:i + batch]
        enc = tok([texts[j] for j in idx], padding=True, truncation=True, max_length=128, return_tensors="pt")
        h = model(**enc).last_hidden_state
        m = enc["attention_mask"].unsqueeze(-1).to(h.dtype)
        e = (h * m).sum(1) / m.sum(1).clamp(min=1e-9)               # mean pooling over real tokens only
        out[idx] = torch.nn.functional.normalize(e, dim=-1).numpy()
        real += int(enc["attention_mask"].sum())
        padded += enc["attention_mask"].numel()
    return out, real, padded


torch.set_num_threads(4)
all_texts = [t for v in splits.values() for t, _ in v]
_, real_u, pad_u = encode(all_texts[:4096], sort=False)
_, real_s, pad_s = encode(all_texts[:4096], sort=True)
print(f"padding on 4096 texts, batch 128: unsorted {pad_u:,} token slots for {real_u:,} real tokens "
      f"({pad_u / real_u:.2f}x); length-sorted {pad_s:,} ({pad_s / real_s:.2f}x)")

t0 = time.perf_counter()
emb = {}
for k, v in splits.items():
    emb[k], _, _ = encode([t for t, _ in v])
dt = time.perf_counter() - t0
n = sum(len(v) for v in splits.values())
print(f"encoded {n:,} utterances in {dt:.1f} s ({n / dt:,.0f}/s, 4 threads, length-sorted batches of 128)")
norms = np.linalg.norm(np.vstack(list(emb.values())), axis=1)
print(f"embedding norms: min {norms.min():.6f} max {norms.max():.6f} (unit vectors -> dot product == cosine)")
assert np.abs(norms - 1).max() < 1e-5

print("\nsingle-query latency (tokenize + forward + pool), 200 test queries, one measured run:")
queries = [t for t, _ in splits["test"][:200]]
for threads in (1, 4):
    torch.set_num_threads(threads)
    for q in queries[:10]:
        encode([q], batch=1)
    ts = []
    for q in queries:
        t1 = time.perf_counter()
        encode([q], batch=1)
        ts.append((time.perf_counter() - t1) * 1e3)
    print(f"  {threads} thread(s): p50 {np.percentile(ts, 50):.2f} ms, p95 {np.percentile(ts, 95):.2f} ms, "
          f"p99 {np.percentile(ts, 99):.2f} ms")
torch.set_num_threads(4)

y = {k: np.array([lab_id.get(lab, -1) for _, lab in v]) for k, v in splits.items()}
np.savez_compressed(os.path.join(DATA, "clinc_minilm.npz"), **{f"X_{k}": emb[k] for k in emb}, **{f"y_{k}": y[k] for k in y})
json.dump({"labels": labels, "texts": {k: [t for t, _ in v] for k, v in splits.items()}},
          open(os.path.join(DATA, "clinc_meta.json"), "w", encoding="utf-8"))

q = emb["test"][0]
nn = np.argsort(-(emb["train"] @ q))[:3]
print(f"\nsanity: query '{splits['test'][0][0]}' ({splits['test'][0][1]}) -> nearest train utterances:")
for j in nn:
    print(f"  {float(emb['train'][j] @ q):.3f}  '{splits['train'][j][0]}' ({splits['train'][j][1]})")
assert splits["train"][nn[0]][1] == splits["test"][0][1]
print("cached: clinc_minilm.npz, clinc_meta.json")
print("\nALL ASSERTIONS PASSED")
```

Output (verified; the throughput and latency lines are one measured run):

```text
CLINC150 split sizes: train=15000, val=3000, test=4500, oos_train=100, oos_val=100, oos_test=1000; 150 intents
encoder: 22,713,216 params, hidden 384, 6 layers; pooling mean=True; modules ['Transformer', 'Pooling', 'Normalize']
padding on 4096 texts, batch 128: unsorted 85,632 token slots for 44,781 real tokens (1.91x); length-sorted 61,952 (1.38x)
encoded 23,700 utterances in 51.7 s (458/s, 4 threads, length-sorted batches of 128)
embedding norms: min 1.000000 max 1.000000 (unit vectors -> dot product == cosine)

single-query latency (tokenize + forward + pool), 200 test queries, one measured run:
  1 thread(s): p50 9.43 ms, p95 18.55 ms, p99 23.04 ms
  4 thread(s): p50 6.10 ms, p95 8.21 ms, p99 9.26 ms

sanity: query 'how would you say fly in italian' (translate) -> nearest train utterances:
  0.644  'how can i say i love you in italy' (translate)
  0.639  'can you give me the answers in italian instead of english' (change_language)
  0.633  'i want you to address me in italian' (change_language)
cached: clinc_minilm.npz, clinc_meta.json

ALL ASSERTIONS PASSED
```

How to read it:

- **The modules line** is the model card in code: Transformer → mean Pooling → Normalize. If your vendor or library skips the Normalize step, add it (01.1 F1).
- **Padding 1.91× → 1.38×** from sorting by length. The same trick applies to any batched encoder job: indexing, backfills, offline evals.
- **The sanity check is a real near-miss.** "how would you say fly in italian" (translate) has a nearest neighbour from `translate`, but the next two are `change_language` utterances at nearly the same cosine (0.639, 0.633). That's exactly the kind of sibling-intent confusion a linear head learns to separate better than a centroid.

### 3.2 Linear and logistic regression from first principles

```python
"""linear_logistic_from_scratch.py - linear and logistic regression from first principles, checked against scikit-learn.

  1. OLS: closed form == gradient descent == sklearn; GD step count explodes with the condition number,
     and standardizing features fixes it.
  2. Ridge = MAP with a Gaussian prior: (X^T X + lam I)^-1 X^T y shrinks every coefficient.
  3. Logistic regression: gradient X^T(sigmoid(Xw) - y), Hessian X^T S X; GD vs Newton (IRLS) iteration counts;
     our Newton solution == sklearn's lbfgs solution.
  4. Separable data: without regularization ||w|| grows forever and probabilities saturate to 0/1.
  5. L1 selects features (sparse w); L2 only shrinks them.
"""
import numpy as np
from sklearn.linear_model import Lasso, LinearRegression, LogisticRegression

rng = np.random.default_rng(31)

print("== 1. OLS three ways, and conditioning ==")
n, d = 2000, 20
X = rng.standard_normal((n, d))
w_true = rng.standard_normal(d)
y = X @ w_true + 0.5 * rng.standard_normal(n)
Xb = np.hstack([X, np.ones((n, 1))])
w_closed = np.linalg.solve(Xb.T @ Xb, Xb.T @ y)                  # normal equations
sk = LinearRegression().fit(X, y)
print(f"closed form vs sklearn: max |dw| = {np.abs(w_closed[:-1] - sk.coef_).max():.2e}")


def gd_steps(A, b, tol=1e-6, max_steps=200_000):
    """Gradient descent on 0.5/n ||Aw - b||^2 with the optimal fixed step 1/L; returns steps to tolerance."""
    H = A.T @ A / len(A)
    L = np.linalg.eigvalsh(H).max()
    w = np.zeros(A.shape[1])
    w_star = np.linalg.solve(A.T @ A, A.T @ b)
    for t in range(1, max_steps + 1):
        w -= (A.T @ (A @ w - b) / len(A)) / L
        if np.linalg.norm(w - w_star) < tol * np.linalg.norm(w_star):
            return t, np.linalg.cond(H)
    return max_steps, np.linalg.cond(H)


print(f"{'features':28s} {'cond(X^T X)':>12} {'GD steps to 1e-6':>17}")
for name, scale in (("standardized", np.ones(d)), ("raw: scales 1..100", np.geomspace(1, 100, d)),
                    ("raw: scales 1..1000", np.geomspace(1, 1000, d))):
    A = np.hstack([X * scale, np.ones((n, 1))])
    steps, cond = gd_steps(A, y)
    capped = " (hit the 200,000 cap)" if steps == 200_000 else ""
    print(f"{name:28s} {cond:>12.1f} {steps:>17,}{capped}")
    if name == "standardized":
        base_steps = steps
assert steps > 100 * base_steps

print("\n== 2. ridge = MAP with prior w ~ N(0, sigma^2/lam I) ==")
print(f"true ||w|| = {np.linalg.norm(w_true):.4f}")
for lam in (0.0, 10.0, 100.0, 1000.0):
    w_r = np.linalg.solve(X.T @ X + lam * np.eye(d), X.T @ y)
    print(f"lambda {lam:>7.1f}: ||w|| = {np.linalg.norm(w_r):.4f}")

print("\n== 3. logistic regression: GD vs Newton vs sklearn ==")
Xl = rng.standard_normal((3000, 10))
wl = rng.standard_normal(10)
yl = (rng.random(3000) < 1 / (1 + np.exp(-(Xl @ wl)))).astype(float)
C = 1.0                                                           # sklearn: C = 1/lambda, L2 on weights (not intercept)
A = np.hstack([Xl, np.ones((3000, 1))])
reg = np.r_[np.ones(10), 0.0] / C
sig = lambda z: 1 / (1 + np.exp(-z))


def loss_grad_hess(w):
    p = sig(A @ w)
    loss = -np.sum(yl * np.log(p + 1e-15) + (1 - yl) * np.log(1 - p + 1e-15)) + 0.5 * np.sum(reg * w * w)
    g = A.T @ (p - yl) + reg * w                                  # the p - y gradient, now for a linear model
    H = (A * (p * (1 - p))[:, None]).T @ A + np.diag(reg)          # X^T S X, S = diag(p(1-p))
    return loss, g, H


w = np.zeros(11)
newton_it = 0
while True:
    newton_it += 1
    _, g, H = loss_grad_hess(w)
    w -= np.linalg.solve(H, g)
    if np.linalg.norm(g) < 1e-8:
        break
w_newton = w
w = np.zeros(11)
Lg = np.linalg.eigvalsh(A.T @ A).max() / 4 + 1 / C               # p(1-p) <= 1/4 bounds the curvature
gd_it = 0
while np.linalg.norm(loss_grad_hess(w)[1]) > 1e-6 and gd_it < 100_000:
    w -= loss_grad_hess(w)[1] / Lg
    gd_it += 1
skl = LogisticRegression(C=C, tol=1e-10, max_iter=10_000).fit(Xl, yl)
print(f"Newton (IRLS) iterations: {newton_it}; gradient descent iterations: {gd_it:,}")
print(f"max |w_newton - w_sklearn| = {np.abs(w_newton[:-1] - skl.coef_[0]).max():.2e} "
      f"(intercept diff {abs(w_newton[-1] - skl.intercept_[0]):.2e})")
assert np.abs(w_newton[:-1] - skl.coef_[0]).max() < 1e-4 and newton_it < 15

print("\n== 4. separable data: the unregularized MLE does not exist ==")
Xs = rng.standard_normal((200, 2))
ys = (Xs[:, 0] + Xs[:, 1] > 0).astype(float)
print(f"{'C':>8} {'||w||':>9} {'max p':>14} {'mean |p - 0.5|':>15}")
norms = []
for Cs in (0.1, 1.0, 100.0, 1e4, 1e6):
    m = LogisticRegression(C=Cs, max_iter=100_000, tol=1e-12).fit(Xs, ys)
    p = m.predict_proba(Xs)[:, 1]
    norms.append(np.linalg.norm(m.coef_))
    print(f"{Cs:>8.0e} {norms[-1]:>9.2f} {p.max():>14.10f} {np.mean(np.abs(p - 0.5)):>15.4f}")
assert norms[-1] > 20 * norms[1]

print("\n== 5. L1 vs L2: 200 features, 10 informative ==")
Xf = rng.standard_normal((500, 200))
coef = np.zeros(200)
coef[:10] = rng.choice([-1, 1], 10) * rng.uniform(1, 3, 10)
yf = Xf @ coef + 0.5 * rng.standard_normal(500)
print(f"{'alpha':>7} {'L1 nonzero':>10} {'true found':>10} {'L2 nonzero':>10}")
for alpha in (0.01, 0.05, 0.2, 0.5):
    l1 = Lasso(alpha=alpha, max_iter=50_000).fit(Xf, yf)
    l2 = np.linalg.solve(Xf.T @ Xf + alpha * 500 * np.eye(200), Xf.T @ yf)
    nz = np.flatnonzero(np.abs(l1.coef_) > 1e-8)
    print(f"{alpha:>7.2f} {len(nz):>10} {len(set(nz) & set(range(10))):>10} {int(np.sum(np.abs(l2) > 1e-8)):>10}")
    if alpha == 0.2:
        assert len(set(nz) & set(range(10))) == 10 and len(nz) < 30
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. OLS three ways, and conditioning ==
closed form vs sklearn: max |dw| = 4.66e-15
features                      cond(X^T X)  GD steps to 1e-6
standardized                          1.5                12
raw: scales 1..100                10274.0           120,006
raw: scales 1..1000             1025140.1           200,000 (hit the 200,000 cap)

== 2. ridge = MAP with prior w ~ N(0, sigma^2/lam I) ==
true ||w|| = 4.1026
lambda     0.0: ||w|| = 4.0879
lambda    10.0: ||w|| = 4.0678
lambda   100.0: ||w|| = 3.8956
lambda  1000.0: ||w|| = 2.7405

== 3. logistic regression: GD vs Newton vs sklearn ==
Newton (IRLS) iterations: 8; gradient descent iterations: 452
max |w_newton - w_sklearn| = 3.37e-09 (intercept diff 2.01e-09)

== 4. separable data: the unregularized MLE does not exist ==
       C     ||w||          max p  mean |p - 0.5|
   1e-01      1.98   0.9933140549          0.2845
   1e+00      4.91   0.9999962789          0.4026
   1e+02     21.84   1.0000000000          0.4861
   1e+04     85.94   1.0000000000          0.4981
   1e+06    251.03   1.0000000000          0.4999

== 5. L1 vs L2: 200 features, 10 informative ==
  alpha L1 nonzero true found L2 nonzero
   0.01        120         10        200
   0.05         21         10        200
   0.20         10         10        200
   0.50         10         10        200

ALL ASSERTIONS PASSED
```

How to read it:

- **Part 1** is the conditioning lesson in one table: same problem, κ from 1.5 to 1,025,140, and GD steps from 12 to more than 200,000.
- **Part 3:** Newton's 8 iterations vs gradient descent's 452 is the practical meaning of second-order information, and why lbfgs is the default.
- **Part 4:** on separable data, every 100× less regularization roughly doubles to triples ‖w‖ and pushes probabilities closer to 0/1. Nothing converges to an answer.

### 3.3 A softmax-regression head on CLINC: regularization, data, calibration, serving

```python
"""logreg_head_on_clinc.py - a softmax-regression head on frozen MiniLM embeddings (CLINC150, 150 intents).

  1. Regularization path: C controls bias vs variance (train vs validation accuracy).
  2. Learning curve: examples per intent vs accuracy (Ng's "do we need more data?" test).
  3. Calibration: logistic regression vs LinearSVC (+ sigmoid / isotonic calibration) vs Gaussian naive Bayes,
     plus temperature scaling of the LR head.
  4. Serving: the head is a 150 x 384 matrix; sklearn's per-call overhead vs a raw NumPy matvec.
"""
import json
import os
import time

import numpy as np
from sklearn.calibration import CalibratedClassifierCV
from sklearn.linear_model import LogisticRegression
from sklearn.naive_bayes import GaussianNB
from sklearn.svm import LinearSVC

DATA = os.environ["KB_DATA"]
Z = np.load(os.path.join(DATA, "clinc_minilm.npz"))
Xtr, ytr, Xva, yva, Xte, yte = (Z[k] for k in ("X_train", "y_train", "X_val", "y_val", "X_test", "y_test"))
labels = json.load(open(os.path.join(DATA, "clinc_meta.json"), encoding="utf-8"))["labels"]


def ece(p, y, bins=15):
    conf, pred = p.max(1), p.argmax(1)
    edges = np.linspace(0, 1, bins + 1)
    return sum(np.mean(m) * abs(conf[m].mean() - (pred[m] == y[m]).mean())
               for lo, hi in zip(edges[:-1], edges[1:]) if (m := (conf > lo) & (conf <= hi)).any())


def nll(p, y):
    return float(-np.mean(np.log(p[np.arange(len(y)), y] + 1e-12)))


print("== 1. regularization path (multinomial LR, lbfgs) ==")
print(f"{'C':>6} {'train acc':>9} {'val acc':>8} {'val NLL':>8} {'||W||_F':>8}")
models = {}
for C in (0.1, 1.0, 10.0, 100.0):
    m = LogisticRegression(C=C, max_iter=3000, tol=1e-4).fit(Xtr, ytr)
    models[C] = m
    print(f"{C:>6} {m.score(Xtr, ytr):>9.4f} {m.score(Xva, yva):>8.4f} {nll(m.predict_proba(Xva), yva):>8.4f} "
          f"{np.linalg.norm(m.coef_):>8.1f}")
best_C = max(models, key=lambda c: models[c].score(Xva, yva))
lr = models[best_C]
print(f"best C on validation = {best_C}; test accuracy {lr.score(Xte, yte):.4f}")
assert models[0.1].score(Xtr, ytr) < models[100.0].score(Xtr, ytr)

print("\n== 2. learning curve at the best C ==")
rng = np.random.default_rng(0)
print(f"{'per intent':>10} {'train rows':>10} {'val acc':>8}")
curve = []
for k in (5, 10, 25, 50, 100):
    idx = np.concatenate([rng.choice(np.flatnonzero(ytr == c), k, replace=False) for c in range(150)])
    acc = LogisticRegression(C=best_C, max_iter=3000, tol=1e-4).fit(Xtr[idx], ytr[idx]).score(Xva, yva)
    curve.append(acc)
    print(f"{k:>10} {len(idx):>10,} {acc:>8.4f}")
assert curve[-1] > curve[0]

print("\n== 3. calibration on the in-scope test set ==")
heads = {
    f"LogisticRegression C={best_C}": lr,
    "LinearSVC + sigmoid (3-fold)": CalibratedClassifierCV(LinearSVC(C=0.5), method="sigmoid", cv=3).fit(Xtr, ytr),
    "LinearSVC + isotonic (3-fold)": CalibratedClassifierCV(LinearSVC(C=0.5), method="isotonic", cv=3).fit(Xtr, ytr),
    "GaussianNB": GaussianNB().fit(Xtr, ytr),
}
print(f"{'head':34s} {'acc':>7} {'NLL':>7} {'ECE':>7} {'mean conf':>9}")
res = {}
for name, h in heads.items():
    p = h.predict_proba(Xte)
    res[name] = nll(p, yte)
    print(f"{name:34s} {np.mean(p.argmax(1) == yte):>7.4f} {nll(p, yte):>7.4f} {res[name]:>7.4f} {p.max(1).mean():>9.4f}")
logits_va, logits_te = lr.decision_function(Xva), lr.decision_function(Xte)
sm = lambda z: np.exp(z - z.max(1, keepdims=True)) / np.exp(z - z.max(1, keepdims=True)).sum(1, keepdims=True)
Ts = np.geomspace(0.2, 5, 200)
T = Ts[int(np.argmin([nll(sm(logits_va / t), yva) for t in Ts]))]
p_t = sm(logits_te / T)
print(f"{'LR + temperature T=' + format(T, '.2f'):34s} {np.mean(p_t.argmax(1) == yte):>7.4f} {nll(p_t, yte):>7.4f} "
      f"{ece(p_t, yte):>7.4f} {p_t.max(1).mean():>9.4f}")
assert res["GaussianNB"] > 3 * res[f"LogisticRegression C={best_C}"] and ece(p_t, yte) < 0.5 * ece(lr.predict_proba(Xte), yte)

print("\n== 4. serving the head (one measured run, 1 thread) ==")
W, b = lr.coef_.astype(np.float32), lr.intercept_.astype(np.float32)
q = Xte[:1]
assert np.allclose(sm(q @ W.T + b), lr.predict_proba(q), atol=1e-4)
for name, fn in (("sklearn predict_proba(1 row)", lambda: lr.predict_proba(q)),
                 ("NumPy W @ q + b, softmax", lambda: sm(q @ W.T + b)),
                 ("NumPy, batch of 256 (per query)", lambda: sm(Xte[:256] @ W.T + b))):
    fn()
    t0 = time.perf_counter()
    for _ in range(500):
        fn()
    per = (time.perf_counter() - t0) / 500 / (256 if "batch" in name else 1)
    print(f"{name:34s} {per * 1e6:8.1f} us")
print(f"head size: {W.nbytes + b.nbytes:,} bytes (fp32) -> ship it as an .npy, not a pickled estimator")
print("\nALL ASSERTIONS PASSED")
```

Output (verified; part 4 timings are one measured run):

```text
== 1. regularization path (multinomial LR, lbfgs) ==
     C train acc  val acc  val NLL  ||W||_F
   0.1    0.9401   0.9143   2.2204     59.9
   1.0    0.9805   0.9513   0.5454    134.9
  10.0    0.9975   0.9600   0.2296    216.7
 100.0    0.9993   0.9560   0.1769    328.4
best C on validation = 10.0; test accuracy 0.9547

== 2. learning curve at the best C ==
per intent train rows  val acc
         5        750   0.8657
        10      1,500   0.9010
        25      3,750   0.9347
        50      7,500   0.9517
       100     15,000   0.9597

== 3. calibration on the in-scope test set ==
head                                   acc     NLL     ECE mean conf
LogisticRegression C=10.0           0.9547  0.2278  0.2278    0.8786
LinearSVC + sigmoid (3-fold)        0.9478  0.2651  0.2651    0.8537
LinearSVC + isotonic (3-fold)       0.9436  0.5189  0.5189    0.9134
GaussianNB                          0.9142  1.7778  1.7778    0.9973
LR + temperature T=0.63             0.9547  0.1645  0.0062    0.9535

== 4. serving the head (one measured run, 1 thread) ==
sklearn predict_proba(1 row)          127.7 us
NumPy W @ q + b, softmax               18.1 us
NumPy, batch of 256 (per query)         2.3 us
head size: 231,000 bytes (fp32) -> ship it as an .npy, not a pickled estimator

ALL ASSERTIONS PASSED
```

How to read it:

- **Serving: 116 µs vs 15.7 µs.** `predict_proba` on one row spends most of its time on input validation and dispatch. The same math as a raw NumPy matvec plus softmax takes 15.7 µs, and 2.3 µs per query in a batch of 256. Export `coef_` and `intercept_` as arrays and serve them with NumPy (or fold them into the ONNX graph, 02.3). Don't put a pickled estimator on the hot path: version skew between the training and serving library versions is a separate class of incident.
- **The assertion line** encodes two production truths: NB's NLL is more than 3× LR's, and temperature scaling at least halves the LR head's ECE.

---

## 4. The Andrew Ng Lens: Diagnose Before You Collect, Calibrate Before You Threshold

### 4.1 The two-number diagnosis

Ng's workflow starts with two numbers: training error and dev error, compared against a reasonable estimate of achievable error. For the CLINC head at C = 10: train 99.75%, val 96.0%. Published human or achievable error isn't available for CLINC, but the remaining errors (§3.1's sanity check is typical) concentrate on genuinely confusable sibling intents. So:

- **Avoidable bias is small.** The model fits the training set.
- **The 3.75-point gap is variance or ambiguity.** More data helps slowly (the learning curve flattens), so look at *which* examples fail before deciding. 02.3 builds that error-analysis table.

### 4.2 Learning curves as a budget tool

Before funding a labelling round, plot accuracy against examples per class on a log scale. CLINC's curve gains about 2 points per doubling at the low end and less than 1 at the high end. If a stakeholder asks "will 2× more labels fix it?", the curve answers before anyone labels anything.

### 4.3 Data-centric checks that beat model changes

- **Label consistency:** CLINC's sibling intents (`translate` vs `change_language`, `transfer` vs `pay_bill`) are where annotator disagreement lives. Fix the intent definitions first.
- **Train/serve parity:** the encoder version, pooling and normalization at training time must match serving exactly. A head trained on unnormalized vectors and served normalized vectors (or the reverse) silently loses accuracy. Store the encoder version with the head.
- **Dev set from the deployment distribution:** CLINC's validation set has 3.2% out-of-scope queries and its test set 18%. Threshold choices made on one don't transfer to the other without reweighting (02.3).

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | "lbfgs failed to converge" and odd coefficients | Mixed feature scales (embedding + raw counts or prices) | Ill-conditioning (κ in the millions) | `StandardScaler` on non-embedding features; raise `max_iter` | A pipeline with the scaler inside it; a convergence warning fails CI |
| F2 | Probabilities of exactly 0/1, terrible NLL on new data | Weak or no regularization on separable data | The MLE doesn't exist (§1.6) | Tune C on validation NLL; calibrate | Never set `penalty=None` on high-dimensional heads |
| F3 | Thresholds behave unpredictably | ECE high; confidence ≠ accuracy | Head mis-calibrated (under-confident at C = 10 here) | Temperature scaling (T = 0.63 here) or Platt | ECE + NLL in the model card; refit T on each retrain |
| F4 | Accuracy drops after "only" an encoder upgrade | Head trained on old-encoder vectors | Spaces aren't comparable (01.1 §1.1) | Retrain the head on new embeddings | Head metadata pins the encoder version; deploy them together |
| F5 | Router p99 latency much higher than benchmarks | `predict_proba` per request on the hot path | sklearn per-call overhead (116 µs vs 15.7 µs) | Serve exported arrays with NumPy, or inside the ONNX graph | A latency budget per stage, measured in CI |
| F6 | Batch embedding jobs are slow and expensive | Padding ratio ~1.9× | Unsorted batches | Length-bucketed batching (1.38×) | Track the padding ratio as a job metric |
| F7 | Short texts embed poorly in mixed batches | Mean pooling includes padding positions | Missing attention-mask weighting | Mask-weighted mean pooling | A unit test: embedding is invariant to batch composition |
| F8 | A model selected on accuracy gives worse probabilities | Best-accuracy C ≠ best-NLL C | Different selection criteria | Select on the metric the consumer uses, then calibrate | Document which metric chose the hyperparameters |
| F9 | SVM-based head "probabilities" fail cost thresholds | Raw margins used as scores | Margins aren't probabilities | `CalibratedClassifierCV` (sigmoid or isotonic) | Only calibrated scores cross a service boundary |
| F10 | L1 run drops a feature the business needs | The sparse solution picks one of several correlated features | Lasso is unstable under collinearity | Elastic-net, or stability selection across bootstraps | Don't read L1 support as causal importance |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why a logistic-regression head instead of fine-tuning the encoder for intent routing?"</b></summary>

**Initial Prompt.** 150 intents, 100 examples each, a latency budget of a few milliseconds.

**L5 Answer.** "Fine-tuning is always more accurate. Fine-tune BERT on the intents."

**Why L5 Fails in Production.** It skips the measurement and the operating cost. A fine-tuned encoder is a model per task. Every class change becomes a GPU training job, and the shared-embedding economics (one vector feeding router, cache, guardrail and retrieval) disappear.

**L7 Principal Defense.** "Start with the frozen encoder plus an LR head, because it's measurable in an hour. On CLINC it reaches 0.955 test accuracy with a 15.7 µs head, and training takes seconds, so class changes are a CI job. The learning curve flattens (0.952 → 0.960 from 50 to 100 per intent), so more data won't move it much. If error analysis shows the remaining errors are representational (sibling intents the encoder doesn't separate), the next step is a few-shot contrastive fine-tune of the encoder (SetFit-style, Folder 04) or a small MLP head. Either way, the frozen pipeline stays as the baseline and fallback."

**Bar-Raiser Follow-ups.**
- *"What would make you fine-tune immediately?"* A domain where the base encoder is weak (heavy jargon, another language: 02.3's German prompts), measured as low accuracy even on the training set (avoidable bias).
- *"How do you serve two heads that need different encoders?"* You don't, if you can avoid it. Shared encoders are the cost advantage, so justify any second encoder with measured gains.

</details>

<details><summary><b>Q2 · "Our training job logs 'lbfgs failed to converge'. Should we just raise max_iter?"</b></summary>

**Initial Prompt.** The head uses MiniLM embeddings concatenated with message length in characters and the account age in days.

**L5 Answer.** "Yes, set max_iter=10000."

**Why L5 Fails in Production.** That hides the cause: the extra features are on scales of 10²–10³ next to unit-norm embedding coordinates. The condition number explodes, and the solver takes forever or stops at a poor point.

**L7 Principal Defense.** "Convergence speed of first-order methods scales with the condition number κ. Our measurement: 12 GD steps at κ = 1.5 vs more than 200,000 at κ ≈ 10⁶ for the same problem. L-BFGS is less sensitive, but not immune. So: put a `StandardScaler` on the non-embedding columns inside the pipeline (so it's fitted on training data only), keep max_iter modest, and make convergence warnings fail CI. Then re-tune C, because the regularizer's effect depends on the feature scale too."

**Bar-Raiser Follow-ups.**
- *"Why not scale the embedding columns too?"* They're already unit-norm and comparably scaled. Per-dimension standardization of embeddings can amplify noise dimensions (01.2's whitening lesson).
- *"Does scaling change the predictions?"* With regularization, yes: the penalty sees the scaled weights. That's another reason the scaler must live inside the fitted pipeline.

</details>

<details><summary><b>Q3 · "Derive the gradient of logistic regression and tell me why the loss is convex."</b></summary>

**Initial Prompt.** A whiteboard question.

**L5 Answer.** "The gradient is (prediction − label) × x. It's convex because it's a standard loss."

**Why L5 Fails in Production.** The formula is right, but the convexity argument is missing, and that's the part with consequences: different solvers give the same answer, and there are no bad local minima to restart from.

**L7 Principal Defense.** "With p = σ(Xw), L = −Σ[y log p + (1−y) log(1−p)] + ½λ‖w‖². Since σ′ = σ(1 − σ), the chain rule gives ∇L = Xᵀ(p − y) + λw. Differentiate again: ∇²L = XᵀSX + λI with S = diag(p(1−p)) ≥ 0, which is PSD, and PD for λ > 0. So the loss is (strictly) convex, with a single global optimum. Consequences: Newton converges in a handful of steps (8 in our run, vs 452 for GD) and matches scikit-learn's lbfgs to 3e-9. Solver choice is a speed and memory decision, not a quality decision."

**Bar-Raiser Follow-ups.**
- *"Softmax version?"* ∇_W L = (P − Y)ᵀX, with P the n × K probability matrix and Y one-hot. The Hessian is block-structured from diag(p) − ppᵀ (01.3 §1.11).
- *"When isn't it strictly convex?"* With λ = 0 and either collinear features or separable data, where the optimum is non-unique or at infinity (§1.6).

</details>

<details><summary><b>Q4 · "Our head's probabilities are 'too low'. The PM wants to raise the confidence threshold. What's going on?"</b></summary>

**Initial Prompt.** The CLINC-style head is right 95% of the time, but its average confidence is 0.88.

**L5 Answer.** "Lower the threshold to compensate."

**Why L5 Fails in Production.** Lowering the threshold changes coverage, not calibration. Every downstream consumer of the probability (a cascade, a cost threshold, an analytics dashboard) still sees the wrong number.

**L7 Principal Defense.** "That's under-confidence from L2 regularization: C = 10 shrinks the logits. Measured: mean confidence 0.879 at 0.955 accuracy, ECE 0.076. Fit a temperature on validation NLL. It comes out at T = 0.63, sharpening, which takes ECE to 0.006 and NLL from 0.228 to 0.165, with accuracy unchanged because argmax is invariant. Then set the escalation threshold on the *calibrated* scores, where 'confidence ≥ 0.9' means about 90% correct. Refit T at every retrain, since it depends on C and the data."

**Bar-Raiser Follow-ups.**
- *"Why not just pick a larger C?"* That changes the model's variance too. Calibration is a separate, cheap, post-hoc fix, so don't entangle the two.
- *"Isotonic instead?"* Lower ECE in our SVC test (0.033), but worse NLL (0.519), because the step function gives near-zero probability to some correct answers. Prefer temperature or Platt for small validation sets.

</details>

<details><summary><b>Q5 · "When would you use L1 instead of L2?"</b></summary>

**Initial Prompt.** A guardrail model with 200 engineered features, some expensive to compute online.

**L5 Answer.** "L1 when you want sparsity."

**Why L5 Fails in Production.** It's true, but it doesn't say why sparsity matters here, or what L1 is bad at (unstable selection among correlated features).

**L7 Principal Defense.** "L1 is MAP under a Laplace prior. Its diamond-shaped constraint makes exact zeros likely, so it performs feature selection. In our test with 10 informative features out of 200, Lasso at α = 0.2 kept exactly the 10 true ones while ridge kept all 200. That directly cuts serving cost when features are expensive (lookups, regexes, external calls). Caveats: among correlated features, L1 picks one somewhat arbitrarily, so use elastic-net or stability selection before deleting a feature pipeline. On dense embeddings, L1 buys nothing: coordinates aren't individually meaningful, so L2 is the default there."

**Bar-Raiser Follow-ups.**
- *"Does L1 give calibrated probabilities?"* As well as L2, given tuned strength. Calibrate the final model either way.

</details>

<details><summary><b>Q6 · "We have 5 examples per new intent. Is a linear head viable?"</b></summary>

**Initial Prompt.** A product launch adds 20 intents with few labels.

**L5 Answer.** "No, you need hundreds of examples per class."

**Why L5 Fails in Production.** The learning curve says otherwise: frozen embeddings already encode most of the semantics. Waiting for hundreds of labels delays the launch for a small gain.

**L7 Principal Defense.** "On CLINC, 5 examples per intent already gives 0.866 validation accuracy across *150* intents, and 25 gives 0.935. So ship the head with the few labels, route low-confidence predictions to the LLM fallback (02.3), log the LLM's decisions as candidate labels, audit a sample, and retrain weekly. The learning curve tells you when the marginal label stops paying (about 50 per intent here). SetFit-style contrastive fine-tuning is the next lever for the few-shot regime."

**Bar-Raiser Follow-ups.**
- *"Centroids instead, for 5 examples?"* Prototype heads are the lowest-variance option at tiny n and need no training. Measure both. LR overtakes once there are a few dozen per class.

</details>

<details><summary><b>Q7 · "Why does validation NLL keep improving at C = 100 when accuracy got worse?"</b></summary>

**Initial Prompt.** The regularization path shows val accuracy peaking at C = 10 but NLL lowest at C = 100.

**L5 Answer.** "NLL and accuracy usually agree. It's noise."

**Why L5 Fails in Production.** It's systematic, not noise. The two metrics reward different things, and picking the wrong one for the consumer is a design bug.

**L7 Principal Defense.** "Accuracy only checks the argmax. NLL scores the whole probability. Less regularization (larger C) sharpens the logits, which raises the probability assigned to the many correct predictions faster than it penalizes the few new errors. So NLL improves while a handful of borderline argmaxes flip and accuracy dips (0.9600 → 0.9560). If the consumer thresholds probabilities, select on NLL, or select on accuracy and fix calibration with temperature. If it only uses the argmax, select on accuracy. Write down which one, because it's a product decision."

**Bar-Raiser Follow-ups.**
- *"Brier score?"* A proper scoring rule like NLL, bounded and less sensitive to near-zero probabilities on correct answers. A good companion metric for calibration-sensitive consumers.

</details>

<details><summary><b>Q8 · "How do you serve a scikit-learn head at 10k QPS?"</b></summary>

**Initial Prompt.** The head runs inside a Python microservice.

**L5 Answer.** "Load the pickle at startup and call predict_proba per request; scale horizontally."

**Why L5 Fails in Production.** `predict_proba` costs 116 µs per single-row call, mostly validation overhead, against 15.7 µs for the same math. Pickles also tie serving to the exact training library version and carry deserialization risk.

**L7 Principal Defense.** "Export W (150 × 384) and b as `.npy` files: 231 KB, versioned with the encoder version. Serve with a NumPy matvec plus softmax (15.7 µs per query; 2.3 µs per query in micro-batches of 256), or fold the head into the encoder's ONNX graph so one runtime call returns probabilities. Micro-batch requests over a 1–2 ms window when QPS allows. At 10k QPS the encoder dominates (about 2 ms per query in ONNX int8, 02.3), so most of the capacity planning is for the encoder, not the head."

**Bar-Raiser Follow-ups.**
- *"How do you guarantee parity with the training-time model?"* A golden test: 1,000 fixed inputs, and exported-path probabilities must match `predict_proba` within 1e-5 (the listing asserts 1e-4).

</details>

---

## 7. Invariants Checklist

- [ ] Embeddings are mask-weighted mean-pooled and L2-normalized exactly as the model card specifies. The same code runs in training and serving.
- [ ] Batch encoding is length-bucketed, and the padding ratio is tracked.
- [ ] Non-embedding features are standardized inside the fitted pipeline. Convergence warnings fail CI.
- [ ] Every head is regularized. C is selected on the metric the consumer uses (accuracy for argmax, NLL for probabilities).
- [ ] Every head ships with NLL, ECE and a fitted temperature (or Platt) in its model card, refit on each retrain.
- [ ] Heads are served from exported arrays (or ONNX), not pickled estimators. A golden parity test guards the export.
- [ ] Head metadata pins the encoder version, and encoder upgrades retrain every head.
- [ ] Labelling budgets are justified by a learning curve.
- [ ] L1 feature selection is validated for stability before features are removed.

---

## 8. References

1. S. Larson et al., *An Evaluation Dataset for Intent Classification and Out-of-Scope Prediction* (CLINC150), EMNLP 2019. https://arxiv.org/abs/1909.02027 (data: https://github.com/clinc/oos-eval)
2. `sentence-transformers/all-MiniLM-L6-v2` model card. https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
3. N. Reimers, I. Gurevych, *Sentence-BERT*, EMNLP 2019. https://arxiv.org/abs/1908.10084
4. W. Wang et al., *MiniLM: Deep Self-Attention Distillation for Task-Agnostic Compression of Pre-Trained Transformers*, 2020. https://arxiv.org/abs/2002.10957
5. scikit-learn user guide, *Linear Models* (logistic regression, solvers, regularization). https://scikit-learn.org/stable/modules/linear_model.html
6. scikit-learn user guide, *Probability calibration*. https://scikit-learn.org/stable/modules/calibration.html
7. A. Niculescu-Mizil, R. Caruana, *Predicting Good Probabilities with Supervised Learning*, ICML 2005. DOI 10.1145/1102351.1102430.
8. R. Tibshirani, *Regression Shrinkage and Selection via the Lasso*, JRSS-B 58(1), 1996. DOI 10.1111/j.2517-6161.1996.tb02080.x.
9. A. Hoerl, R. Kennard, *Ridge Regression: Biased Estimation for Nonorthogonal Problems*, Technometrics 12(1), 1970. DOI 10.1080/00401706.1970.10488634.
10. S. Boyd, L. Vandenberghe, *Convex Optimization* (Cambridge, 2004; free PDF). https://web.stanford.edu/~boyd/cvxbook/
11. L. Tunstall et al., *Efficient Few-Shot Learning Without Prompts* (SetFit), 2022. https://arxiv.org/abs/2209.11055
12. A. Ng, *Machine Learning Yearning* (bias/variance, learning curves). https://www.deeplearning.ai/resources/
