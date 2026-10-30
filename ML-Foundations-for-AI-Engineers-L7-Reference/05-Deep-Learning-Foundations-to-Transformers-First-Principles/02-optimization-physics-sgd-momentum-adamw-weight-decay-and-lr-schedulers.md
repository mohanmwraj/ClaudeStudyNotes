# 05.2 · Optimization Physics: SGD, Momentum, AdamW, Weight Decay & LR Schedulers

> **Folder 05 · Deep Learning Foundations to Transformers, from First Principles**
> **Measured on:** NumPy 2.5.4 (optimizer trajectories), PyTorch 2.14.1 (CPU, 2 threads: AdamW, schedulers, an MLP head on CLINC150 MiniLM embeddings), Windows 11.
> **Design sources:** Polyak (heavy-ball momentum, 1964), Nesterov (1983), Kingma & Ba (Adam, ICLR 2015), Loshchilov & Hutter (AdamW, ICLR 2019; SGDR, 2017), Goyal et al. (linear scaling and warmup, 2017), Smith (LR range test, 2017). Full list in §8.

---

## 0. Orientation: The Optimizer Is a Physical System You Can Reason About

Here's the Andrew Ng-style version. **Gradient descent walks downhill. Momentum gives it inertia so it doesn't zig-zag in narrow valleys. Adam gives every parameter its own step size, so badly scaled directions don't stall it. Weight decay pulls weights toward zero. The learning-rate schedule decides how big the steps are over time.** Each piece has a mechanism you can predict and measure:

- **Momentum** on a condition-number-100 quadratic: 95 steps instead of GD's 709. Theory predicts ~69 vs ~691.
- **Adam** under a 100× gradient rescaling of one coordinate: the *identical* trajectory (351 steps), while GD diverges.
- **L2 inside Adam vs AdamW**: L2-in-Adam applies **17× less** decay per step to large-gradient weights (1.46e-3 vs 2.50e-2). AdamW applies a uniform 1.00e-2.
- **An LR range test** on a real head: one epoch per learning rate shows that 1e-5 learns nothing and 1e-2 is near the edge.

For an AI engineer who fine-tunes adapters, heads and small models (Folders 01.2, 02, 04, 07), this is the difference between "the run didn't converge" and knowing why.

### The backend-engineer bridge

| You already know | Optimization equivalent |
|---|---|
| A control loop with gain tuning (PID) | **Learning rate** = gain; too high oscillates or diverges, too low is sluggish |
| Exponential smoothing of a noisy metric | **Momentum / Adam moments**: EWMAs of gradients and squared gradients |
| Per-tenant rate limits normalized by each tenant's traffic | **Adam's per-parameter step**: g/√v normalizes each coordinate by its own gradient scale |
| Slow-start (TCP) then steady state, then backoff | **Warmup → peak → cosine decay** |
| Config drift between a library default and a paper's setting | **`weight_decay` in Adam ≠ weight decay in AdamW** |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 Gradient descent and the condition number (recap) | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Momentum (heavy ball) and Nesterov | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 Stochastic gradients and batch size | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 RMSProp and Adam: per-parameter step sizes | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Adam's bias correction | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.6 Weight decay: L2-in-Adam vs decoupled AdamW | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Learning-rate schedules: warmup, cosine, and why | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Finding the learning rate: the range test | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 Gradient clipping and loss spikes | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.10 Newer optimizers (Lion, Sophia, Muon, Shampoo) | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 Convergence proofs for non-convex SGD | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 Gradient descent and the condition number (recap) `[MUST-KNOW: Core AI Engineer Edge]`

02.1 §1.3 derived it. On a quadratic with curvatures μ (smallest) and L (largest), GD with the optimal step 2/(L + μ) shrinks the error by (κ − 1)/(κ + 1) per step, with κ = L/μ. At κ = 100 that's 0.9802 per step, so ~691 steps to 1e-6. We measured **709**. Neural network losses are not quadratic, but *locally* they have directions of very different curvature, so the same physics applies.

### 1.2 Momentum (heavy ball) and Nesterov `[MUST-KNOW: Core AI Engineer Edge]`

```text
heavy ball (Polyak):  v ← β·v + ∇f(x);   x ← x − η·v
Nesterov:             v ← β·v + ∇f(x − η·β·v);   x ← x − η·v        (gradient at the look-ahead point)
```

Momentum accumulates gradients that keep pointing the same way (along the valley floor) and cancels those that flip sign (across the valley):

```text
   GD on a narrow valley                    with momentum
   ╲  ╱╲  ╱╲  ╱╲  ╱  → slow progress        ────────────────►  oscillations damp, speed builds
    ╲╱  ╲╱  ╲╱  ╲╱                           (the across-valley component averages out)
```

With optimally tuned β and η on a quadratic, the rate becomes (√κ − 1)/(√κ + 1): 0.8182 per step at κ = 100, so ~69 steps. We measured **95** for heavy ball and 208 for Nesterov at a generic β = 0.9. Momentum turns a κ-dependence into a √κ-dependence, which is why SGD with momentum 0.9 is the classical default.

### 1.3 Stochastic gradients and batch size `[MUST-KNOW: Core AI Engineer Edge]`

Real training uses minibatch gradients: unbiased estimates of the true gradient, with variance ∝ 1/batch. Two production consequences:

- **Noise sets a floor.** With a constant learning rate, SGD bounces around the minimum at a radius proportional to η × noise. That's one reason schedules *decay* η (§1.7).
- **The linear scaling rule** (Goyal et al., 2017): when you multiply the batch size by k, multiply the learning rate by about k (for SGD, up to a limit), with warmup. Bigger batches mean less noise per step, so you can take bigger steps. Adam is less linear (often square-root scaling works better), and LoRA tolerates large batches less well than full fine-tuning (01.2 §1.8). Re-tune the learning rate whenever you change the batch size substantially.

### 1.4 RMSProp and Adam: per-parameter step sizes `[MUST-KNOW: Core AI Engineer Edge]`

```text
m ← β₁ m + (1 − β₁) g            (EWMA of gradients:         direction, like momentum)
v ← β₂ v + (1 − β₂) g²           (EWMA of squared gradients: per-parameter scale)
x ← x − η · m̂ / (√v̂ + ε)          m̂, v̂ bias-corrected (§1.5);  defaults β₁ = 0.9, β₂ = 0.999
```

Dividing by √v normalizes each coordinate by its own recent gradient magnitude, so **Adam's step size is roughly η in parameter units, whatever the gradient scale.** The listing demonstrates the exact invariance. Make coordinate 2's gradient 100× larger (as a loss term or feature 100× larger in scale would):

```text
GD (lr tuned for the original)   steps:  20000  (final ||x|| = nan)
Adam lr 0.01                     steps:    351  (final ||x|| = 9.2e-07)
```

GD's stable step size is now 100× too large, and it diverges. Adam's g/√v is unchanged by a per-coordinate gradient scale, so its trajectory is **identical** (351 steps, the same as the unscaled problem). This is why Adam dominates for transformers, where embedding rows, attention projections, norms and biases have wildly different gradient scales.

Two caveats the numbers expose:

- Adam isn't invariant to *reparameterizing* the coordinates themselves. Its steps are fixed in parameter units, so a parameter that needs to travel 100 units at η = 0.01 takes ~10,000 steps. That's one reason initialization scale and learning rate interact.
- On the plain quadratic, Adam (351 steps) was slower than tuned momentum (95). Adaptivity buys robustness, not always speed.

On Rosenbrock's curved valley (2,000 steps from (−1.5, 2)), Adam got closest (f = 7.7e-3), momentum 0.19, RMSProp 2.4, and GD stalled at 5.3.

### 1.5 Adam's bias correction `[GOOD-TO-KNOW: Architectural Literacy]`

m and v start at zero, so their early EWMAs are biased toward zero. Dividing by (1 − βᵗ) corrects that:

```text
bias correction on : 0.0100, 0.0100, 0.0100, 0.0100, 0.0100
bias correction off: 0.0316, 0.0425, 0.0495, 0.0544, 0.0580
```

Without correction, v̂ is far more biased than m̂ early on (β₂ = 0.999 vs β₁ = 0.9), so the first updates are 3–6× too *large*. With correction, the first step is about η regardless of the gradient's magnitude. That's one reason Adam is "safe to start". Warmup (§1.7) addresses the remaining early instability.

### 1.6 Weight decay: L2-in-Adam vs decoupled AdamW `[MUST-KNOW: Core AI Engineer Edge]`

With plain SGD, adding an L2 penalty ½λ‖w‖² to the loss is identical to shrinking weights by (1 − ηλ) each step. **With Adam it isn't.** The L2 gradient λw gets divided by √v like every other gradient, so weights with large gradient magnitudes are barely decayed. Loshchilov & Hutter's fix, **AdamW**, applies the decay *outside* the adaptive step: w ← w − η·λ·w. The listing reads Adam's second-moment state after training and computes the decay actually applied per step:

```text
optimizer                                      final mean w    per-step decay applied to w
                                        large-scale / small            large-scale / small
Adam + L2 (weight_decay=1 in Adam)      0.9915 / 0.6744         1.46e-03 / 2.50e-02
AdamW (decoupled, weight_decay=1)       0.8074 / 0.4851         1.00e-02 / 1.00e-02
```

With L2 inside Adam, the weights with 10× larger feature scale (and so larger gradients) receive **17× less** decay per step than the others. The regularization strength depends on gradient statistics, which nobody chose. AdamW applies exactly lr × wd = 1e-2 to every weight. (In both cases the final weights still differ by group, because the data term's pull on each weight differs. What AdamW fixes is that the *regularizer* is uniform and controllable.)

**The production trap:** `torch.optim.Adam(..., weight_decay=0.01)` is L2-in-Adam, while `torch.optim.AdamW(..., weight_decay=0.01)` is decoupled decay. The same argument name, two different algorithms. Papers and fine-tuning recipes (LoRA Without Regret, most LLM training) mean AdamW. Common practice also excludes biases and norm gains from decay, via parameter groups.

### 1.7 Learning-rate schedules: warmup, cosine, and why `[MUST-KNOW: Core AI Engineer Edge]`

```text
warmup:   η(t) = η_peak · t / T_w                                   for t < T_w
cosine:   η(t) = η_peak · ½(1 + cos(π (t − T_w)/(T − T_w)))          afterwards, decaying to ~0
```

The listing computes it by hand and with PyTorch's `SequentialLR(LinearLR, CosineAnnealingLR)`, and they agree (5.00e-04 at step 550, 1.17e-04 at 800).

- **Warmup** protects the early phase, when Adam's v estimates are still forming, weights are random, and gradients can be large and erratic. It matters most at large batch sizes, with post-norm architectures (05.1 §1.8), and when fine-tuning pre-trained weights you don't want to wreck in the first steps.
- **Decay** lowers the noise floor of §1.3 and lets the optimizer settle into a minimum. Cosine (from SGDR) is the common default, and linear decay is equally common for fine-tuning.

On the CLINC MLP head (8 epochs, peak 3e-3), the schedule mattered little: constant 0.9457, cosine 0.9493, warmup + cosine 0.9483. A 0.3–0.4-point spread is within run-to-run noise for 3,000 validation examples. Schedules matter far more for long runs and large models than for an 8-epoch head. Don't let schedule tuning displace data work (§4).

### 1.8 Finding the learning rate: the range test `[MUST-KNOW: Core AI Engineer Edge]`

The learning rate is the single most important hyperparameter. Sweep it on a log scale with a short budget each (Smith, 2017):

```text
  lr 1e-05: train loss after 1 epoch 5.014, val acc 0.0047
  lr 1e-04: train loss after 1 epoch 4.978, val acc 0.0937
  lr 1e-03: train loss after 1 epoch 2.984, val acc 0.7027
  lr 1e-02: train loss after 1 epoch 0.194, val acc 0.9160
  lr 1e-01: train loss after 1 epoch 1.459, val acc 0.8417
```

At 1e-5 the loss sits at **5.014 ≈ ln 150 = 5.01**, the loss of a uniform guess over 150 classes: nothing learned. 1e-2 is best after one epoch, and 1e-1 is already past the edge (the loss is higher and noisier). For a longer run, pick a peak somewhat *below* the one-epoch best (we used 3e-3 for 8 epochs), because the fastest learning rate in one epoch is often unstable over many. When the loss at step 0 isn't ≈ ln K, there's a bug before there's a tuning problem (05.1 §4.1).

### 1.9 Gradient clipping and loss spikes `[GOOD-TO-KNOW: Architectural Literacy]`

Clip the global gradient norm (`clip_grad_norm_(params, 1.0)`) so that one bad batch can't take a huge step. It's standard in transformer training, and 05.3's RNN listing uses it because recurrent gradients can explode. Clipping treats the symptom: persistent clipping means the learning rate is too high or something upstream is unstable (fp16 overflow, a missing norm, bad data). Monitor the *fraction of clipped steps*.

### 1.10 Newer optimizers (Lion, Sophia, Muon, Shampoo) `[GOOD-TO-KNOW: Architectural Literacy]`

Lion (sign-based updates, less optimizer memory), Sophia (cheap second-order curvature estimates), Shampoo/SOAP (preconditioning with matrix factors) and Muon (orthogonalized updates for matrix-shaped parameters) report faster pre-training in some settings. For an AI engineer fine-tuning heads, adapters and small models, AdamW with a tuned learning rate, warmup and decay remains the robust default. Adopt alternatives only with an ablation on your own task.

### 1.11 Convergence proofs for non-convex SGD `[SKIP: Academic/Research Only]`

Rates to stationary points, saddle-point escape, and edge-of-stability dynamics explain observed behaviour but don't change the practical recipe: tune the learning rate, use warmup and decay, clip gradients, AdamW.

---

## 2. Where It Beats an LLM in Production

Optimization is the toolkit for **training the cheap models that replace LLM calls**: heads on frozen embeddings (02), query adapters (04.2), LoRA adapters (01.2), distilled students (Folder 07). Getting the optimizer right is what makes those models train in minutes on a CPU instead of failing silently:

| Cheap model | Optimizer recipe that worked in this KB |
|---|---|
| Logistic-regression head | L-BFGS (convex, so no learning-rate tuning; 02.1) |
| MLP head on embeddings | AdamW, peak LR from a range test, cosine decay (§3.2) |
| Query-side retrieval adapter | Adam, small LR (1e-3), identity init, a penalty toward the identity (04.2) |
| LoRA adapter | Adam(W) at ~10× the full-fine-tuning LR, α/r scaling (01.2) |

---

## 3. Production Code Blueprint

### 3.1 Optimizer trajectories on controlled geometry

```python
"""optimizer_physics.py - SGD, momentum, Nesterov, RMSProp and Adam on problems whose geometry we control.

  1. Ill-conditioned quadratic (kappa = 100): steps to reach 1e-6, vs the theoretical rates
     GD ~ (kappa-1)/(kappa+1) per step, heavy-ball momentum ~ (sqrt(kappa)-1)/(sqrt(kappa)+1).
  2. Diagonal rescaling: multiply one coordinate by 100. GD breaks; Adam's per-coordinate step barely notices.
  3. Adam's bias correction: the size of the first updates with and without it.
  4. Rosenbrock's curved valley: how far each optimizer gets in 2,000 steps.
"""
import numpy as np

print("== 1. quadratic f(x) = 0.5 x^T diag(1, kappa) x, kappa = 100, start (1, 1) ==")
kappa = 100.0
Hd = np.array([1.0, kappa])
grad = lambda x: Hd * x


def run(opt, x0, lr, steps=20_000, tol=1e-6, gfun=grad, **kw):
    x = x0.copy()
    v = np.zeros_like(x)
    m = np.zeros_like(x)
    s = np.zeros_like(x)
    for t in range(1, steps + 1):
        g = gfun(x)
        if opt == "gd":
            x = x - lr * g
        elif opt == "momentum":
            v = kw["beta"] * v + g
            x = x - lr * v
        elif opt == "nesterov":
            g_ahead = gfun(x - lr * kw["beta"] * v)
            v = kw["beta"] * v + g_ahead
            x = x - lr * v
        elif opt == "rmsprop":
            s = 0.99 * s + 0.01 * g * g
            x = x - lr * g / (np.sqrt(s) + 1e-8)
        elif opt == "adam":
            m = 0.9 * m + 0.1 * g
            s = 0.999 * s + 0.001 * g * g
            mh = m / (1 - 0.9 ** t) if kw.get("bias_correct", True) else m
            sh = s / (1 - 0.999 ** t) if kw.get("bias_correct", True) else s
            x = x - lr * mh / (np.sqrt(sh) + 1e-8)
        if np.linalg.norm(x) < tol:
            return t, x
    return steps, x


L, mu = kappa, 1.0
beta_opt = ((np.sqrt(kappa) - 1) / (np.sqrt(kappa) + 1)) ** 2
lr_mom = (2 / (np.sqrt(L) + np.sqrt(mu))) ** 2
x0 = np.array([1.0, 1.0])
res = {}
for name, opt, lr, kw in (("GD, lr = 2/(L+mu)", "gd", 2 / (L + mu), {}), ("heavy-ball momentum (optimal)", "momentum", lr_mom, {"beta": beta_opt}),
                          ("Nesterov", "nesterov", 1 / L, {"beta": 0.9}), ("Adam lr 0.01", "adam", 0.01, {})):
    t, x = run(opt, x0, lr, **kw)
    res[name] = t
    print(f"{name:32s} steps to ||x|| < 1e-6: {t:>6}")
print(f"theory: GD error x {(kappa - 1) / (kappa + 1):.4f}/step -> ~{np.log(1e-6) / np.log((kappa - 1) / (kappa + 1)):.0f} steps; "
      f"momentum x {(np.sqrt(kappa) - 1) / (np.sqrt(kappa) + 1):.4f}/step -> ~{np.log(1e-6) / np.log((np.sqrt(kappa) - 1) / (np.sqrt(kappa) + 1)):.0f} steps")
assert res["heavy-ball momentum (optimal)"] < res["GD, lr = 2/(L+mu)"] / 5

print("\n== 2. make coordinate 2's gradient 100x larger (e.g. a loss term or feature with 100x the scale) ==")
g_big = lambda x: grad(x) * np.array([1.0, 100.0])                 # curvature along x2: 100 -> 10,000
for name, opt, lr in (("GD (lr tuned for the original)", "gd", 2 / (L + mu)), ("Adam lr 0.01", "adam", 0.01)):
    with np.errstate(over="ignore", invalid="ignore"):
        t, x = run(opt, x0, lr, gfun=g_big)
    print(f"{name:32s} steps: {t:>6}  (final ||x|| = {np.linalg.norm(x):.1e})")
print("GD's stable step size is now 100x too large -> it diverges; Adam's update g/sqrt(v) is unchanged by a")
print("per-coordinate gradient scale, so its trajectory is identical (its step sizes are in PARAMETER units)")

print("\n== 3. Adam bias correction: size of the first five updates (lr 0.01, constant gradient 1e-3) ==")
for bc in (True, False):
    m = s = 0.0
    steps = []
    for t in range(1, 6):
        g = 1e-3
        m, s = 0.9 * m + 0.1 * g, 0.999 * s + 0.001 * g * g
        mh, sh = (m / (1 - 0.9 ** t), s / (1 - 0.999 ** t)) if bc else (m, s)
        steps.append(0.01 * mh / (np.sqrt(sh) + 1e-8))
    print(f"bias correction {'on ' if bc else 'off'}: " + ", ".join(f"{u:.4f}" for u in steps))
print("with it, the first step is ~lr regardless of gradient scale; without it, early steps are mis-scaled")

print("\n== 4. Rosenbrock f = (1-x)^2 + 100 (y - x^2)^2 from (-1.5, 2), 2,000 steps ==")
rb = lambda p: np.array([-2 * (1 - p[0]) - 400 * p[0] * (p[1] - p[0] ** 2), 200 * (p[1] - p[0] ** 2)])
f_rb = lambda p: (1 - p[0]) ** 2 + 100 * (p[1] - p[0] ** 2) ** 2
for name, opt, lr, kw in (("GD lr 1e-4", "gd", 1e-4, {}), ("momentum lr 1e-4, beta 0.9", "momentum", 1e-4, {"beta": 0.9}),
                          ("RMSProp lr 1e-3", "rmsprop", 1e-3, {}), ("Adam lr 1e-2", "adam", 1e-2, {})):
    _, p = run(opt, np.array([-1.5, 2.0]), lr, steps=2000, tol=0, gfun=rb, **kw)
    print(f"{name:28s} f = {f_rb(p):.2e} at ({p[0]:+.3f}, {p[1]:+.3f})  (minimum 0 at (1, 1))")
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. quadratic f(x) = 0.5 x^T diag(1, kappa) x, kappa = 100, start (1, 1) ==
GD, lr = 2/(L+mu)                steps to ||x|| < 1e-6:    709
heavy-ball momentum (optimal)    steps to ||x|| < 1e-6:     95
Nesterov                         steps to ||x|| < 1e-6:    208
Adam lr 0.01                     steps to ||x|| < 1e-6:    351
theory: GD error x 0.9802/step -> ~691 steps; momentum x 0.8182/step -> ~69 steps

== 2. make coordinate 2's gradient 100x larger (e.g. a loss term or feature with 100x the scale) ==
GD (lr tuned for the original)   steps:  20000  (final ||x|| = nan)
Adam lr 0.01                     steps:    351  (final ||x|| = 9.2e-07)
GD's stable step size is now 100x too large -> it diverges; Adam's update g/sqrt(v) is unchanged by a
per-coordinate gradient scale, so its trajectory is identical (its step sizes are in PARAMETER units)

== 3. Adam bias correction: size of the first five updates (lr 0.01, constant gradient 1e-3) ==
bias correction on : 0.0100, 0.0100, 0.0100, 0.0100, 0.0100
bias correction off: 0.0316, 0.0425, 0.0495, 0.0544, 0.0580
with it, the first step is ~lr regardless of gradient scale; without it, early steps are mis-scaled

== 4. Rosenbrock f = (1-x)^2 + 100 (y - x^2)^2 from (-1.5, 2), 2,000 steps ==
GD lr 1e-4                   f = 5.34e+00 at (-1.309, +1.722)  (minimum 0 at (1, 1))
momentum lr 1e-4, beta 0.9   f = 1.94e-01 at (+0.560, +0.312)  (minimum 0 at (1, 1))
RMSProp lr 1e-3              f = 2.44e+00 at (-0.557, +0.324)  (minimum 0 at (1, 1))
Adam lr 1e-2                 f = 7.67e-03 at (+0.912, +0.832)  (minimum 0 at (1, 1))

ALL ASSERTIONS PASSED
```

### 3.2 AdamW vs L2-in-Adam, schedules, and an LR range test on a real head

```python
"""adamw_and_lr_schedules.py - L2-in-Adam vs decoupled weight decay (AdamW), and learning-rate schedules, in PyTorch.

  1. Adam + L2 penalty vs AdamW on a problem where features have very different gradient scales:
     with L2 inside Adam the shrinkage depends on each weight's gradient scale; AdamW's does not.
  2. Warmup + cosine decay, computed by hand and by torch's schedulers.
  3. An MLP head on frozen CLINC embeddings: LR range test, then constant vs cosine vs warmup+cosine.
"""
import math
import os

import numpy as np
import torch

torch.manual_seed(0)
torch.set_num_threads(2)

print("== 1. effective weight decay: Adam + L2 vs AdamW ==")
n, d = 4000, 20
X = torch.randn(n, d)
X[:, :10] *= 10.0                                                  # 10 features with 10x larger values -> 100x larger curvature
y = X @ torch.ones(d) + 0.5 * torch.randn(n)                       # every true weight is 1.0
LR, WD, STEPS = 0.01, 1.0, 4000
decay = {}
print(f"{'optimizer':36s} {'final mean w':>22} {'per-step decay applied to w':>30}")
print(f"{'':36s} {'large-scale / small':>22} {'large-scale / small':>30}")
for name, mk in (("Adam + L2 (weight_decay=1 in Adam)", lambda p: torch.optim.Adam(p, lr=LR, weight_decay=WD)),
                 ("AdamW (decoupled, weight_decay=1)", lambda p: torch.optim.AdamW(p, lr=LR, weight_decay=WD))):
    torch.manual_seed(1)
    w = torch.nn.Parameter(torch.zeros(d))
    opt = mk([w])
    for _ in range(STEPS):
        idx = torch.randint(0, n, (64,))
        loss = ((X[idx] @ w - y[idx]) ** 2).mean()
        opt.zero_grad()
        loss.backward()
        opt.step()
    st = opt.state[w]
    v_hat = st["exp_avg_sq"] / (1 - 0.999 ** STEPS)
    if name.startswith("AdamW"):
        rate = torch.full((d,), LR * WD)                            # w <- w - lr*wd*w, outside the adaptive step
    else:
        rate = LR * WD / (v_hat.sqrt() + 1e-8)                      # the L2 gradient wd*w is divided by sqrt(v)
    decay[name] = (rate[:10].mean().item(), rate[10:].mean().item())
    print(f"{name:36s} {w[:10].mean().item():>9.4f} / {w[10:].mean().item():<9.4f}  "
          f"{decay[name][0]:>12.2e} / {decay[name][1]:<12.2e}")
print("with L2 inside Adam, weights whose gradients are large (high v) get a much SMALLER decay per step;")
print("AdamW's decoupled decay is the same multiplicative pull lr*wd for every weight (Loshchilov & Hutter).")
print("final weights still differ by group in both: the data term's pull is per-weight in any optimizer.")
l2 = decay["Adam + L2 (weight_decay=1 in Adam)"]
aw = decay["AdamW (decoupled, weight_decay=1)"]
assert l2[1] / l2[0] > 5 and abs(aw[1] / aw[0] - 1) < 1e-9

print("\n== 2. warmup + cosine schedule (peak 1e-3, warmup 100 of 1,000 steps) ==")
peak, warm, total = 1e-3, 100, 1000
def lr_at(t):
    return peak * t / warm if t < warm else peak * 0.5 * (1 + math.cos(math.pi * (t - warm) / (total - warm)))
p = torch.nn.Parameter(torch.zeros(1))
opt = torch.optim.AdamW([p], lr=peak)
sched = torch.optim.lr_scheduler.SequentialLR(opt, [
    torch.optim.lr_scheduler.LinearLR(opt, start_factor=1e-8, end_factor=1.0, total_iters=warm),
    torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=total - warm)], milestones=[warm])
got = []
for t in range(total):
    got.append(opt.param_groups[0]["lr"])
    opt.step()
    sched.step()
for t in (0, 50, 100, 300, 550, 800, 999):
    print(f"  step {t:>4}: hand {lr_at(t):.2e}  torch {got[t]:.2e}")
assert abs(got[550] - lr_at(550)) < 1e-6

print("\n== 3. MLP head (384 -> 256 -> 150) on frozen CLINC embeddings ==")
Z = np.load(os.path.join(os.environ["KB_DATA"], "clinc_minilm.npz"))
Xtr, ytr = torch.tensor(Z["X_train"]), torch.tensor(Z["y_train"])
Xva, yva = torch.tensor(Z["X_val"]), torch.tensor(Z["y_val"])


def make():
    torch.manual_seed(0)
    return torch.nn.Sequential(torch.nn.Linear(384, 256), torch.nn.GELU(), torch.nn.Dropout(0.1), torch.nn.Linear(256, 150))


print("LR range test (one epoch per LR, AdamW): ")
for lr in (1e-5, 1e-4, 1e-3, 1e-2, 1e-1):
    m = make()
    o = torch.optim.AdamW(m.parameters(), lr=lr, weight_decay=0.01)
    for idx in torch.randperm(len(Xtr)).split(128):
        loss = torch.nn.functional.cross_entropy(m(Xtr[idx]), ytr[idx])
        o.zero_grad()
        loss.backward()
        o.step()
    m.eval()
    print(f"  lr {lr:.0e}: train loss after 1 epoch {loss.item():.3f}, val acc {(m(Xva).argmax(1) == yva).float().mean().item():.4f}")

EPOCHS, steps_per_epoch = 8, math.ceil(len(Xtr) / 128)
total = EPOCHS * steps_per_epoch
print(f"\n{EPOCHS} epochs at peak lr 3e-3:")
acc = {}
for name in ("constant", "cosine", "warmup 10% + cosine"):
    m = make()
    o = torch.optim.AdamW(m.parameters(), lr=3e-3, weight_decay=0.01)
    if name == "cosine":
        s = torch.optim.lr_scheduler.CosineAnnealingLR(o, T_max=total)
    elif name.startswith("warmup"):
        w = total // 10
        s = torch.optim.lr_scheduler.SequentialLR(o, [torch.optim.lr_scheduler.LinearLR(o, 1e-3, 1.0, total_iters=w),
                                                      torch.optim.lr_scheduler.CosineAnnealingLR(o, T_max=total - w)], [w])
    else:
        s = None
    torch.manual_seed(0)
    for _ in range(EPOCHS):
        m.train()
        for idx in torch.randperm(len(Xtr)).split(128):
            loss = torch.nn.functional.cross_entropy(m(Xtr[idx]), ytr[idx])
            o.zero_grad()
            loss.backward()
            o.step()
            if s:
                s.step()
    m.eval()
    with torch.no_grad():
        acc[name] = (m(Xva).argmax(1) == yva).float().mean().item()
    print(f"  {name:22s} val acc {acc[name]:.4f}")
print("(02.1's logistic-regression head reached 0.9600 on the same validation set)")
assert acc["cosine"] >= acc["constant"] - 0.01
print("\nALL ASSERTIONS PASSED")
```

Output (verified):

```text
== 1. effective weight decay: Adam + L2 vs AdamW ==
optimizer                                      final mean w    per-step decay applied to w
                                        large-scale / small            large-scale / small
Adam + L2 (weight_decay=1 in Adam)      0.9915 / 0.6744         1.46e-03 / 2.50e-02    
AdamW (decoupled, weight_decay=1)       0.8074 / 0.4851         1.00e-02 / 1.00e-02    
with L2 inside Adam, weights whose gradients are large (high v) get a much SMALLER decay per step;
AdamW's decoupled decay is the same multiplicative pull lr*wd for every weight (Loshchilov & Hutter).
final weights still differ by group in both: the data term's pull is per-weight in any optimizer.

== 2. warmup + cosine schedule (peak 1e-3, warmup 100 of 1,000 steps) ==
  step    0: hand 0.00e+00  torch 1.00e-11
  step   50: hand 5.00e-04  torch 5.00e-04
  step  100: hand 1.00e-03  torch 1.00e-03
  step  300: hand 8.83e-04  torch 8.83e-04
  step  550: hand 5.00e-04  torch 5.00e-04
  step  800: hand 1.17e-04  torch 1.17e-04
  step  999: hand 3.05e-09  torch 3.05e-09

== 3. MLP head (384 -> 256 -> 150) on frozen CLINC embeddings ==
LR range test (one epoch per LR, AdamW): 
  lr 1e-05: train loss after 1 epoch 5.014, val acc 0.0047
  lr 1e-04: train loss after 1 epoch 4.978, val acc 0.0937
  lr 1e-03: train loss after 1 epoch 2.984, val acc 0.7027
  lr 1e-02: train loss after 1 epoch 0.194, val acc 0.9160
  lr 1e-01: train loss after 1 epoch 1.459, val acc 0.8417

8 epochs at peak lr 3e-3:
  constant               val acc 0.9457
  cosine                 val acc 0.9493
  warmup 10% + cosine    val acc 0.9483
(02.1's logistic-regression head reached 0.9600 on the same validation set)

ALL ASSERTIONS PASSED
```

---

## 4. The Andrew Ng Lens: Tune the Learning Rate First, Then Stop Tuning

### 4.1 Ng's hyperparameter priority

Ng's Deep Learning Specialization ranks the learning rate as the most important hyperparameter, followed by momentum/β, batch size and model size, with Adam's β₁/β₂/ε rarely worth touching. Our measurements agree: the LR range test spans "learns nothing" (val accuracy 0.005) to 0.916 across four orders of magnitude, while the schedule choice moved accuracy by 0.4 points. Spend tuning budget in that order, and sample learning rates on a **log scale**.

### 4.2 Bias and variance in the optimizer's terms

- **High training loss** (bias): the learning rate is too low or too high (check the range test), too few steps, or a model too small. Optimizer fixes come first because they're cheapest.
- **Low training loss, high validation loss** (variance): weight decay (AdamW, properly decoupled), dropout, early stopping, more data. Note that weight decay strength is only *meaningful* in AdamW form, where it doesn't depend on gradient statistics (§1.6).

### 4.3 The data-centric reminder

The MLP head with the best schedule (0.9493) still lost to plain logistic regression (0.9600) on the same frozen embeddings. Optimizer craft can't beat the right model class for the data, so measure the simple baseline first.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Loss stuck at ln K from step 0 | 5.01 for 150 classes | Learning rate far too low (1e-5 here), or frozen parameters | LR range test; check `requires_grad` | Step-0 and step-100 loss assertions in CI |
| F2 | Loss explodes or NaN | Diverging after a few steps | LR too high (GD diverged at 100× curvature) | Lower the LR, warmup, gradient clipping | Range test before every new setup |
| F3 | "Weight decay doesn't regularize the big layers" | Large-gradient weights barely shrink | L2 inside Adam (17× weaker decay per step there) | AdamW (decoupled); exclude norms and biases via param groups | Lint: `Adam(..., weight_decay>0)` flagged |
| F4 | Paper recipe doesn't reproduce | Same "weight_decay" number, different optimizer | Adam vs AdamW semantics | Match the optimizer, not just the value | Record the optimizer class in experiment metadata |
| F5 | Training unstable in the first few hundred steps | Early spikes | No warmup with a large batch, post-norm, or a fresh head on a pre-trained body | Linear warmup (5–10% of steps) | Warmup by default for fine-tuning |
| F6 | Changing the batch size broke a working run | Same LR, 8× batch | LR not rescaled | Linear (SGD) or ~√ (Adam) scaling + re-tune | The LR is re-tuned on any batch change |
| F7 | Validation keeps wobbling at the end | A constant LR at the noise floor | No decay | Cosine or linear decay to ~0 | Schedules are part of the training config |
| F8 | Gradient clipping fires on most steps | High clip fraction | LR too high, or instability upstream | Lower the LR; find the unstable component | Monitor the clip fraction |
| F9 | Slow convergence on a badly scaled problem with SGD | Zig-zag, κ-dependence | Ill-conditioning | Momentum (95 vs 709 steps), Adam, feature scaling | Standardize inputs; prefer adaptive optimizers for heterogeneous parameters |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why does Adam work so well for transformers, and when is it not the right choice?"</b></summary>

**Initial Prompt.** An optimizer-design discussion.

**L5 Answer.** "Adam adapts the learning rate, so it's better than SGD."

**Why L5 Fails in Production.** "Adapts the learning rate" is vague: per what, based on what? And it doesn't say when Adam is slower or wrong.

**L7 Principal Defense.** "Adam divides each parameter's update by the running RMS of its own gradients, so the step is about η in parameter units, whatever the gradient scale. That's exactly invariant to per-coordinate gradient scaling: in our test, a 100× larger gradient on one coordinate made GD diverge while Adam's trajectory was identical (351 steps). Transformers mix embedding rows, projections, norms and biases with wildly different gradient scales, so Adam (properly AdamW) is the default. It's not always fastest: tuned momentum hit the quadratic's tolerance in 95 steps vs Adam's 351. Its memory cost is two extra fp32 states per parameter, which matters at scale (LoRA and 8-bit optimizers address it)."

**Bar-Raiser Follow-ups.**
- *"Why do people still use SGD for vision CNNs?"* Well-tuned SGD + momentum often generalizes slightly better on those architectures, whose parameters are more homogeneous.

</details>

<details><summary><b>Q2 · "What's the difference between Adam with weight_decay and AdamW?"</b></summary>

**Initial Prompt.** A fine-tuning recipe uses `torch.optim.Adam(params, weight_decay=0.01)`.

**L5 Answer.** "They're the same; AdamW is just a newer name."

**Why L5 Fails in Production.** They're different algorithms. With L2 inside Adam, the decay term is divided by √v, so its strength depends on gradient statistics.

**L7 Principal Defense.** "Adam with weight_decay adds λw to the gradient, then normalizes by √v̂, so weights with large gradients get much less decay. We read the optimizer state and measured an effective per-step decay of 1.46e-3 for large-gradient weights vs 2.50e-2 for the rest (17×). AdamW applies w ← w − η·λ·w outside the adaptive step: exactly 1e-2 for every weight. Use AdamW, set decay via parameter groups (exclude biases and norm gains), and when reproducing a paper, match the optimizer class, not just the number."

**Bar-Raiser Follow-ups.**
- *"Does decay strength interact with the learning rate?"* In AdamW the per-step shrink is η·λ, so changing η changes the effective decay. Scale λ consciously when you re-tune η.

</details>

<details><summary><b>Q3 · "How do you pick the learning rate for a new fine-tuning job?"</b></summary>

**Initial Prompt.** A new head or adapter on a new dataset.

**L5 Answer.** "Use 1e-3; it's the Adam default."

**Why L5 Fails in Production.** Our range test on a real head: 1e-3 reached 0.70 after one epoch, 1e-2 reached 0.92, and 1e-5 learned nothing. A default can be 10× off in either direction.

**L7 Principal Defense.** "Run a short LR range test on a log scale (1e-5 … 1e-1), one epoch or a few hundred steps each. Check that the loss at step 0 is ≈ ln K (5.01 for 150 classes). Pick a peak somewhat below the fastest stable value for longer runs (3e-3 here, for 8 epochs), add warmup (5–10%) and cosine or linear decay. For LoRA, start around 10× the full-fine-tuning LR (LoRA Without Regret). Re-run the test when the batch size, model or data change."

**Bar-Raiser Follow-ups.**
- *"Why below the one-epoch best?"* The fastest LR over one epoch sits close to instability, and over many epochs it tends to diverge or settle worse. A bit lower buys stability.

</details>

<details><summary><b>Q4 · "Explain momentum physically, and quantify what it buys."</b></summary>

**Initial Prompt.** A whiteboard question.

**L5 Answer.** "It smooths the gradients."

**Why L5 Fails in Production.** "Smooths" misses the mechanism (accumulating consistent directions, cancelling oscillating ones) and the quantitative gain.

**L7 Principal Defense.** "Heavy ball: v ← βv + g, x ← x − ηv. Along a narrow valley, the across-valley gradient flips sign each step and averages out, while the along-valley gradient accumulates, so the ball builds speed down the valley. On a quadratic with condition number κ, GD's error shrinks by (κ − 1)/(κ + 1) per step and optimally tuned momentum by (√κ − 1)/(√κ + 1). At κ = 100 that's ~691 vs ~69 steps in theory, and we measured 709 vs 95. That √κ is the whole story of why momentum and its descendants (Adam's m) are standard."

**Bar-Raiser Follow-ups.**
- *"Nesterov?"* It evaluates the gradient at the look-ahead point, which corrects overshoot. It's theoretically better, but in our untuned β = 0.9 run it took 208 steps vs optimal heavy ball's 95. Tuning matters more than the variant.

</details>

<details><summary><b>Q5 · "Why do LLM training recipes use warmup?"</b></summary>

**Initial Prompt.** A team removes warmup to simplify the code and sees loss spikes.

**L5 Answer.** "It's a convention from papers."

**Why L5 Fails in Production.** It's a stability mechanism with specific causes, and removing it breaks real runs.

**L7 Principal Defense.** "Early in training: Adam's second-moment estimates are still forming, random weights produce large and erratic gradients, and with large batches the noise-free gradient direction encourages aggressive steps. Post-norm architectures are especially sensitive (05.1 §1.8). Warmup ramps η from ~0 to its peak over the first 1–10% of steps, so the optimizer's statistics settle before full-size steps. Bias correction handles some of this (the first steps are ≈ η, not 3–6× η), and warmup handles the rest. For fine-tuning, it also protects the pre-trained weights from being wrecked by a fresh, randomly initialized head's large early gradients."

**Bar-Raiser Follow-ups.**
- *"How long?"* Typically 1–10% of total steps. The listing's schedule uses 10%, matched by hand and by PyTorch's schedulers.

</details>

<details><summary><b>Q6 · "We doubled the batch size to train faster, and quality dropped. Why?"</b></summary>

**Initial Prompt.** Scaling a fine-tuning job across more GPUs.

**L5 Answer.** "Bigger batches generalize worse; go back."

**Why L5 Fails in Production.** That's partly folklore. The usual culprit is not re-tuning the learning rate (and warmup) for the new batch size.

**L7 Principal Defense.** "Doubling the batch halves gradient variance and the number of steps per epoch. For SGD, the linear scaling rule says double the LR too, with warmup (Goyal et al.). For Adam, scaling is closer to √k, so re-tune. If quality still drops at very large batches, you've hit the regime where gradient noise no longer helps exploration, and some methods (LoRA, per LoRA Without Regret) are more batch-sensitive than full fine-tuning. Measure the LR × batch grid on a short run before committing the compute."

**Bar-Raiser Follow-ups.**
- *"Gradient accumulation?"* It's mathematically a larger batch (same rules apply) with the memory of a small one.

</details>

<details><summary><b>Q7 · "Is the learning-rate schedule worth tuning for our classifier head?"</b></summary>

**Initial Prompt.** A team spends a week on schedule sweeps.

**L5 Answer.** "Yes, cosine schedules always help."

**Why L5 Fails in Production.** On our CLINC head, constant vs cosine vs warmup + cosine differed by 0.4 points (0.9457 / 0.9493 / 0.9483), within noise for 3,000 validation examples. Meanwhile a plain LR head beat all of them (0.9600).

**L7 Principal Defense.** "For short runs on small heads, schedules are second-order. Tune the LR (orders of magnitude matter), use a sensible default schedule (warmup + cosine or linear decay), and spend the rest on error analysis, data and model class. Schedules matter more for long runs and large models, where the noise floor and late-stage convergence dominate. Report run-to-run variance before claiming a schedule win (Folder 06)."

**Bar-Raiser Follow-ups.**
- *"How many seeds?"* At least 3–5 for any claimed difference under ~1 point, plus a paired comparison on the same data splits.

</details>

<details><summary><b>Q8 · "Gradient clipping fires on 40% of steps. Is that fine?"</b></summary>

**Initial Prompt.** Monitoring shows constant clipping in a fine-tuning run.

**L5 Answer.** "Clipping is a safety net; it's fine."

**Why L5 Fails in Production.** Constant clipping means the optimizer is effectively running at a different, gradient-norm-capped step size, which masks a learning rate that's too high or an unstable component.

**L7 Principal Defense.** "Clipping should be rare: a guard against occasional bad batches. At 40%, either the LR is too high (run the range test again), something upstream produces outsized gradients (fp16 overflow, a missing norm, an unnormalized feature, a data bug such as extreme lengths), or the clip threshold is unrealistically low for this model. Check per-layer gradient norms to find the source, fix it, and track the clip fraction as a training-health metric."

**Bar-Raiser Follow-ups.**
- *"Global norm or per-parameter clipping?"* Global-norm clipping preserves the update direction and is the standard for transformers.

</details>

---

## 7. Invariants Checklist

- [ ] Every new training setup starts with an LR range test on a log scale, and the step-0 loss is checked against ln K.
- [ ] AdamW (decoupled decay) is the default. `Adam(..., weight_decay>0)` requires a written justification. Biases and norm gains are excluded from decay.
- [ ] Fine-tuning uses warmup (1–10%) and decay (cosine or linear).
- [ ] The LR is re-tuned on batch-size changes. Gradient accumulation is treated as a larger batch.
- [ ] Gradient clipping is on, with the clip fraction monitored.
- [ ] Claims about schedules or optimizers include multiple seeds and a paired comparison.
- [ ] The optimizer class and every hyperparameter are recorded in experiment metadata.

---

## 8. References

1. B. Polyak, *Some methods of speeding up the convergence of iteration methods* (heavy ball), USSR Comp. Math. & Math. Physics 4(5), 1964.
2. Y. Nesterov, *A method for solving the convex programming problem with convergence rate O(1/k²)*, 1983.
3. D. Kingma, J. Ba, *Adam: A Method for Stochastic Optimization*, ICLR 2015. https://arxiv.org/abs/1412.6980
4. I. Loshchilov, F. Hutter, *Decoupled Weight Decay Regularization* (AdamW), ICLR 2019. https://arxiv.org/abs/1711.05101
5. I. Loshchilov, F. Hutter, *SGDR: Stochastic Gradient Descent with Warm Restarts* (cosine schedules), ICLR 2017. https://arxiv.org/abs/1608.03983
6. P. Goyal et al., *Accurate, Large Minibatch SGD: Training ImageNet in 1 Hour* (linear scaling, warmup), 2017. https://arxiv.org/abs/1706.02677
7. L. Smith, *Cyclical Learning Rates for Training Neural Networks* (LR range test), WACV 2017. https://arxiv.org/abs/1506.01186
8. PyTorch, `torch.optim` (Adam vs AdamW semantics, LR schedulers). https://docs.pytorch.org/docs/stable/optim.html
9. X. Chen et al., *Symbolic Discovery of Optimization Algorithms* (Lion), 2023. https://arxiv.org/abs/2302.06675
10. A. Ng, *Deep Learning Specialization*, Course 2: Improving Deep Neural Networks (hyperparameter tuning, optimization). https://www.deeplearning.ai/courses/deep-learning-specialization/
