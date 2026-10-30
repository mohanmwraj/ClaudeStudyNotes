# 05.1 · MLPs & Backpropagation: Activations (GELU, SwiGLU) and LayerNorm vs RMSNorm

> **Folder 05 · Deep Learning Foundations to Transformers, from First Principles**
> **Measured on:** PyTorch 2.14.1 (CPU, 4 threads), NumPy 2.5.4, CPython 3.14.5, Intel i5-11260H, Windows 11.
> **Design sources:** Rumelhart, Hinton & Williams (1986), Glorot & Bengio (2010), He et al. (2015), Hendrycks & Gimpel (GELU, 2016), Shazeer (*GLU Variants Improve Transformer*, 2020), Ba et al. (LayerNorm, 2016), Zhang & Sennrich (RMSNorm, 2019), Touvron et al. (Llama, 2023). Full list in §8.

---

## 0. Orientation: A Transformer Is MLPs and Attention, Glued with Norms and Residuals

The Andrew Ng-style version: **a neural network is a stack of "multiply by a matrix, add a bias, bend the result with a nonlinearity" layers. Backpropagation is the chain rule run backwards, so one pass gives the gradient for every weight.** A transformer block adds attention (05.3) between two of those MLP layers, a normalization to keep the numbers in range, and residual connections so gradients can flow. Two-thirds of a transformer's parameters are in its MLPs: in Llama-style models, the SwiGLU feed-forward blocks.

An AI engineer needs this layer of understanding to:

- **Read a model config and know what each number costs**: hidden size, MLP ratio, number of layers, norm type, activation.
- **Debug training**: NaNs, vanishing signals, wrong initialization, a frozen layer that isn't frozen.
- **Fine-tune or distil small models** for the cheap tiers of a cascade (Folder 07).
- **Re-implement or verify a model**, which 05.4 does for MiniLM from its raw weights.

### The backend-engineer bridge

| You already know | Deep-learning equivalent |
|---|---|
| A request pipeline of pure functions | **Layers**: `h = σ(Wx + b)` composed many times |
| Distributed tracing: each span records its inputs to explain the outcome later | **The autograd tape**: each op records its parents and a local backward rule |
| Propagating an error budget back through a call graph | **Backprop**: ∂loss/∂(each weight) via the chain rule, in reverse topological order |
| Input normalization and rate limiting to keep downstream stable | **LayerNorm/RMSNorm**: keep activations in a stable range at every layer |
| Connection-pool sizing by a rule of thumb you can derive | **Initialization scale** (Kaiming √(2/n)): derivable, and wrong values break everything |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 The MLP: what each layer computes | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 Backpropagation as reverse-mode automatic differentiation | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.3 The cost of a backward pass | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Activations: ReLU, GELU, SiLU | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.5 Gated FFNs: SwiGLU and the 8/3 rule | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Initialization and signal propagation | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 LayerNorm vs RMSNorm | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 Residual connections and pre-norm vs post-norm | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 Universal approximation and depth-separation theorems | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 The MLP: what each layer computes `[MUST-KNOW: Core AI Engineer Edge]`

```text
h₁ = φ(x W₁ + b₁)          x: (batch, d_in)   W₁: (d_in, d_hidden)
ŷ  = h₁ W₂ + b₂            W₂: (d_hidden, d_out) → logits → softmax cross-entropy (01.3 §1.11)
```

Each linear layer is a matrix (Folder 01: rotate, stretch, rotate). Without the nonlinearity φ, a stack of linear layers collapses to a single linear map (W₁W₂ is just another matrix), so depth buys nothing. The nonlinearity bends space. The network learns piecewise-curved decision boundaries, which no linear head can draw, by composing many simple bends.

That's also why the 384 → 256 → 150 MLP head in 05.2 *didn't* beat a plain logistic-regression head on frozen MiniLM embeddings (0.949 vs 0.960 validation accuracy). The encoder already did the nonlinear work, and the classes are close to linearly separable in its output space. Extra capacity mostly adds variance.

### 1.2 Backpropagation as reverse-mode automatic differentiation `[MUST-KNOW: Core AI Engineer Edge]`

Every operation knows its **vector–Jacobian product** (VJP): given the gradient of the loss with respect to its output, it returns the gradients with respect to its inputs. For the operations in an MLP:

```text
C = A @ B         ∂L/∂A = G Bᵀ           ∂L/∂B = Aᵀ G          (G = ∂L/∂C)
C = A + b         ∂L/∂A = G              ∂L/∂b = Σ_batch G      (broadcast → sum)
c = φ(a)          ∂L/∂a = G ⊙ φ′(a)                             (elementwise gate)
L = CE(softmax z) ∂L/∂z = (p − y)/batch
```

**Backprop** records the computation graph during the forward pass, then visits nodes in *reverse topological order*, multiplying each node's incoming gradient by its local VJP and accumulating into its parents. That's the chain rule organized so each intermediate result is reused. The listing (§3.1) implements this in about 80 lines (a tensor that remembers its parents plus a `backward()` that topologically sorts the graph) and matches PyTorch's autograd on a 2-layer GELU MLP to **~1e-16 in float64**:

```text
  dW1: max |ours - torch| = 2.08e-17
  dW2: max |ours - torch| = 8.33e-17
```

The hand-derived equations make the structure visible: `dW₂ = A₁ᵀ dZ₂` (weight gradients are outer products of the layer's *input activations* and its *output deltas*), and `dA₁ = dZ₂ W₂ᵀ` (deltas flow backwards through the transposed weights, then through φ′). Two production facts follow:

- **Activations must be stored for the backward pass.** Each `Aᵀ G` needs the forward activation A. That's why training memory is dominated by activations at long sequence lengths, and why gradient checkpointing (recompute instead of store) trades compute for memory.
- **A parameter receives gradient only if it's on a path to the loss.** A "frozen" layer that still has `requires_grad=True`, or a detached tensor in the wrong place, silently changes what trains (01.2's LoRA listing asserts that the base weights get no gradient for exactly this reason).

### 1.3 The cost of a backward pass `[MUST-KNOW: Core AI Engineer Edge]`

```text
8,393,728 parameters: forward 24.6 ms, forward+backward 65.2 ms (2.7x)
finite differences would need one forward pass PER parameter: 8,393,728 passes
```

Reverse mode computes **all** 8.4M gradients for about 2–3× the cost of one forward pass. Each matmul's backward is two matmuls (one for the input gradient, one for the weight gradient), hence the rule of thumb **training FLOPs ≈ 3 × forward FLOPs**, or 6 × params × tokens for transformers. Finite differences would need 8.4M forward passes. This asymmetry (one scalar loss, millions of parameters) is why reverse mode, not forward mode, is the default in deep learning.

### 1.4 Activations: ReLU, GELU, SiLU `[GOOD-TO-KNOW: Architectural Literacy]`

```text
  x=-1.0: ReLU +0.0000  GELU -0.1587  SiLU -0.2689
  x=+0.5: ReLU +0.5000  GELU +0.3457  SiLU +0.3112
  x=+2.0: ReLU +2.0000  GELU +1.9545  SiLU +1.7616
```

- **ReLU** max(0, x) has zero gradient for x < 0, so a unit pushed negative for every input stops learning ("dead ReLU").
- **GELU** x·Φ(x) (Hendrycks & Gimpel) weights the input by the probability that a standard normal is below it. It's smooth and slightly negative for small negative inputs. It's BERT's and GPT-2's activation. The common tanh approximation differs from the exact erf form by at most **4.7e-4**, which is small, but a model must be run with the variant it was trained with (`approximate="tanh"` in PyTorch). That's one of the details the from-weights re-implementation in 05.4 has to match.
- **SiLU/Swish** x·σ(x): similar shape, used inside SwiGLU.

### 1.5 Gated FFNs: SwiGLU and the 8/3 rule `[MUST-KNOW: Core AI Engineer Edge]`

Shazeer (2020) found that *gated* feed-forward layers beat plain ones at equal parameter count:

```text
plain FFN:   FFN(x) = GELU(x W₁) W₂                      2 matrices of d × 4d  → 8d² params
SwiGLU FFN:  FFN(x) = (SiLU(x W_gate) ⊙ (x W_up)) W_down  3 matrices of d × h  → 3dh params
equal params ⇒ 3dh = 8d² ⇒ h = 8d/3
```

```text
exact 8/3 d                                    hidden  10922.7: SwiGLU params 3*d*h = 134,217,728 vs GELU MLP 2*d*4d = 134,217,728
Llama-2-7B / Llama-1 (rounded up to a multiple of 256)  hidden  11008.0: SwiGLU params 3*d*h = 135,266,304 ...
```

That's where Llama's odd-looking `intermediate_size = 11008` comes from: 8/3 × 4096 = 10,922.7, rounded up to a multiple of 256 for hardware-friendly matrix shapes. The gate `SiLU(x W_gate)` multiplies elementwise with a second projection, letting each hidden unit switch the other's contribution on or off. When you read a config, `intermediate_size / hidden_size ≈ 2.7` signals a gated FFN, and ≈ 4 signals a plain one.

### 1.6 Initialization and signal propagation `[MUST-KNOW: Core AI Engineer Edge]`

For a layer h = Wx with Wᵢⱼ ~ N(0, σ²) and n inputs, Var(hᵢ) = n·σ²·Var(x). Keeping variance constant needs σ² = 1/n (Xavier/Glorot). But ReLU zeroes half the inputs, halving the second moment each layer. **Kaiming/He initialization** uses σ² = 2/n to compensate. Measured through 50 ReLU layers of width 512:

```text
init                 layer 1  layer 10  layer 25  layer 50
Xavier  1/sqrt(n)   7.05e-01  2.77e-02  1.29e-04  1.77e-08
Kaiming sqrt(2/n)   9.96e-01  9.88e-01  9.33e-01  6.19e-01
```

With Xavier, the signal shrinks by ~√2 per layer, down to 10⁻⁸ by layer 50: the network outputs essentially zero, and gradients vanish the same way. Kaiming keeps it near 1. Modern transformers rely less on initialization alone because normalization layers and residuals (below) keep signals in range, but init still matters. Llama-style and GPT-style models scale the residual-branch output projections down by depth so the residual stream doesn't grow with the number of layers.

### 1.7 LayerNorm vs RMSNorm `[MUST-KNOW: Core AI Engineer Edge]`

```text
LayerNorm(x) = γ ⊙ (x − mean(x)) / √(var(x) + ε) + β        re-centres AND re-scales (2d params)
RMSNorm(x)   = γ ⊙ x / √(mean(x²) + ε)                       re-scales only (d params)
```

The listing measures exactly what each is invariant to:

```text
LayerNorm: change after adding a constant 7: 2.22e-15; after multiplying by 13: 2.45e-07
RMSNorm  : change after adding a constant 7: 1.33e+00; after multiplying by 13: 4.15e-08
```

Both remove the overall **scale** of the activation vector. Only LayerNorm removes a common **shift**. Zhang & Sennrich (2019) argued the re-centring is rarely needed and RMSNorm is cheaper (no mean, no bias). Llama, Mistral, Qwen and most recent decoder LLMs use RMSNorm, while BERT-family encoders (like MiniLM in 05.4) use LayerNorm.

**But "cheaper" depends on the kernel.** On this CPU, PyTorch's fused LayerNorm ran in **7.2 ms** on a 4096 × 4096 tensor, and `torch.nn.RMSNorm` in **20.9 ms**, because LayerNorm dispatches to one fused kernel and RMSNorm here runs as several elementwise ops. The FLOP saving is real, and realized only with a fused implementation (as in the GPU kernels production inference engines ship). Measure on your target, don't assume.

### 1.8 Residual connections and pre-norm vs post-norm `[MUST-KNOW: Core AI Engineer Edge]`

```text
post-norm (original Transformer, BERT, MiniLM):   h = Norm(h + Sublayer(h))
pre-norm  (GPT-2 onward, Llama):                  h = h + Sublayer(Norm(h))
```

The residual `h + …` gives gradients an identity path from the loss straight to early layers: the derivative of h + f(h) is I + f′(h), so even if f′ is tiny, the gradient doesn't vanish. That's the same insight as the LSTM's additive cell state (05.3). **Pre-norm** keeps that identity path completely clean (the norm sits on the branch, not the trunk), which makes very deep stacks train stably without careful learning-rate warmup. **Post-norm** normalizes the trunk itself, which can be slightly better at small depth but is harder to train deep. When re-implementing or porting a model, the norm placement is a correctness detail, not a style choice: 05.4's MiniLM re-implementation is post-norm because BERT is.

### 1.9 Universal approximation and depth-separation theorems `[SKIP: Academic/Research Only]`

A one-hidden-layer network can approximate any continuous function on a compact set given enough units (Cybenko, Hornik). Some functions need exponentially many units at shallow depth but few at greater depth. These theorems explain *why* deep nets are expressive, but say nothing about trainability, data or cost, which are the questions you'll actually face.

---

## 2. Where It Beats an LLM in Production

Folder 05 is mostly about *understanding* LLMs. The practical payoff is knowing when a **small network you can train yourself** is the right tool:

| Need | A small MLP or fine-tuned small encoder | A prompted LLM |
|---|---|---|
| Classification on frozen embeddings | A linear head is often enough (0.960). An MLP adds capacity when the classes aren't linearly separable | A generation per request |
| A learned scoring function on mixed features (embedding + tabular) | An MLP over the concatenation, trained in minutes | Can't consume dense feature vectors natively |
| Edge or CPU deployment | Thousands of parameters to tens of millions, microseconds to milliseconds | Billions of parameters |
| Debuggability | Gradients, activations and weights are all inspectable | Black box behind an API |

Knowing backprop well enough to implement it (§3.1) is what lets you debug when these small models misbehave: wrong frozen layers, vanishing signals, NaNs.

---

## 3. Production Code Blueprint

### 3.1 Reverse-mode autodiff from scratch, checked against PyTorch

```python
"""autograd_from_scratch.py - reverse-mode automatic differentiation in ~80 lines, checked against torch.autograd.

  1. A Tensor that records its parents and a local backward rule; backward() walks the graph in reverse
     topological order applying the chain rule (vector-Jacobian products).
  2. A 2-layer MLP (matmul, bias, GELU, softmax cross-entropy) built on it.
  3. Gradients match PyTorch to float64 precision; the hand-derived backprop equations match too.
  4. Why reverse mode: one backward pass gives ALL parameter gradients at ~2-3x the forward cost.
"""
import time

import numpy as np
import torch


class T:
    def __init__(self, data, parents=(), back=None):
        self.data, self.grad, self.parents, self.back = np.asarray(data, dtype=np.float64), None, parents, back

    def __matmul__(self, o):
        out = T(self.data @ o.data, (self, o))
        out.back = lambda g: (g @ o.data.T, self.data.T @ g)          # VJPs of C = A @ B
        return out

    def __add__(self, o):
        out = T(self.data + o.data, (self, o))
        out.back = lambda g: (g, g.sum(0) if o.data.ndim == 1 else g)  # broadcasting bias: sum over the batch
        return out

    def gelu(self):
        x = self.data
        c = np.sqrt(2 / np.pi)
        u = c * (x + 0.044715 * x ** 3)
        th = np.tanh(u)
        out = T(0.5 * x * (1 + th), (self,))
        out.back = lambda g: (g * (0.5 * (1 + th) + 0.5 * x * (1 - th ** 2) * c * (1 + 3 * 0.044715 * x ** 2)),)
        return out

    def softmax_ce(self, y):
        z = self.data - self.data.max(1, keepdims=True)
        p = np.exp(z) / np.exp(z).sum(1, keepdims=True)
        out = T(-np.mean(np.log(p[np.arange(len(y)), y])), (self,))
        out.back = lambda g: (g * (p - np.eye(p.shape[1])[y]) / len(y),)   # the p - y gradient (01.3 s1.11)
        return out

    def backward(self):
        order, seen = [], set()

        def topo(n):
            if id(n) not in seen:
                seen.add(id(n))
                for p in n.parents:
                    topo(p)
                order.append(n)

        topo(self)
        self.grad = np.ones_like(self.data)
        for n in reversed(order):                                   # reverse topological order
            if n.back is None:
                continue
            for p, g in zip(n.parents, n.back(n.grad)):
                p.grad = g if p.grad is None else p.grad + g


rng = np.random.default_rng(131)
B, DIN, H, C = 32, 20, 64, 5
X, y = rng.standard_normal((B, DIN)), rng.integers(0, C, B)
W1, b1 = rng.standard_normal((DIN, H)) * np.sqrt(2 / DIN), np.zeros(H)
W2, b2 = rng.standard_normal((H, C)) * np.sqrt(1 / H), np.zeros(C)

print("== 1-3. ours vs torch.autograd (float64) ==")
p = [T(W1), T(b1), T(W2), T(b2)]
loss = ((T(X) @ p[0] + p[1]).gelu() @ p[2] + p[3]).softmax_ce(y)
loss.backward()
tp = [torch.tensor(a, requires_grad=True) for a in (W1, b1, W2, b2)]
tl = torch.nn.functional.cross_entropy(
    torch.nn.functional.gelu(torch.tensor(X) @ tp[0] + tp[1], approximate="tanh") @ tp[2] + tp[3], torch.tensor(y))
tl.backward()
print(f"loss: ours {loss.data:.12f}  torch {tl.item():.12f}")
for name, a, b in zip(("W1", "b1", "W2", "b2"), p, tp):
    print(f"  d{name}: max |ours - torch| = {np.abs(a.grad - b.grad.numpy()).max():.2e}")
    assert np.abs(a.grad - b.grad.numpy()).max() < 1e-12

print("\n== hand-derived backprop equations ==")
Z1 = X @ W1 + b1
c = np.sqrt(2 / np.pi)
A1 = 0.5 * Z1 * (1 + np.tanh(c * (Z1 + 0.044715 * Z1 ** 3)))
Z2 = A1 @ W2 + b2
P = np.exp(Z2 - Z2.max(1, keepdims=True))
P /= P.sum(1, keepdims=True)
dZ2 = (P - np.eye(C)[y]) / B                                        # delta at the output
dW2 = A1.T @ dZ2                                                    # outer products of activations and deltas
dA1 = dZ2 @ W2.T                                                    # deltas flow back through W^T
print(f"dW2 = A1^T dZ2: max diff {np.abs(dW2 - p[2].grad).max():.2e};  dA1 = dZ2 W2^T feeds the GELU' gate")
assert np.abs(dW2 - p[2].grad).max() < 1e-12

print("\n== 4. cost of one backward pass vs one forward pass (torch, MLP 1024-4096-1024, batch 256, CPU) ==")
torch.set_num_threads(4)
net = torch.nn.Sequential(torch.nn.Linear(1024, 4096), torch.nn.GELU(), torch.nn.Linear(4096, 1024))
xb = torch.randn(256, 1024)
for _ in range(3):
    net(xb).sum().backward()
t0 = time.perf_counter()
for _ in range(10):
    with torch.no_grad():
        net(xb)
fwd = (time.perf_counter() - t0) / 10
t0 = time.perf_counter()
for _ in range(10):
    net.zero_grad()
    net(xb).sum().backward()
fb = (time.perf_counter() - t0) / 10
n_params = sum(q.numel() for q in net.parameters())
print(f"{n_params:,} parameters: forward {fwd * 1e3:.1f} ms, forward+backward {fb * 1e3:.1f} ms ({fb / fwd:.1f}x)")
print("finite differences would need one forward pass PER parameter: " f"{n_params:,} passes")
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except the ms timings, which are one measured run):

```text
== 1-3. ours vs torch.autograd (float64) ==
loss: ours 1.801632002086  torch 1.801632002086
  dW1: max |ours - torch| = 2.08e-17
  db1: max |ours - torch| = 1.39e-17
  dW2: max |ours - torch| = 8.33e-17
  db2: max |ours - torch| = 1.39e-17

== hand-derived backprop equations ==
dW2 = A1^T dZ2: max diff 0.00e+00;  dA1 = dZ2 W2^T feeds the GELU' gate

== 4. cost of one backward pass vs one forward pass (torch, MLP 1024-4096-1024, batch 256, CPU) ==
8,393,728 parameters: forward 24.6 ms, forward+backward 65.2 ms (2.7x)
finite differences would need one forward pass PER parameter: 8,393,728 passes

ALL ASSERTIONS PASSED
```

### 3.2 Activations, initialization, SwiGLU arithmetic, LayerNorm vs RMSNorm

```python
"""activations_and_norms.py - GELU, SwiGLU, initialization, LayerNorm vs RMSNorm: the numbers behind the choices.

  1. GELU exact (erf) vs the tanh approximation; SiLU; where they differ from ReLU.
  2. Signal propagation through a 50-layer MLP: activation scale per depth with Xavier vs Kaiming init (ReLU).
  3. SwiGLU's parameter arithmetic: why Llama-style FFNs use hidden = 8/3 d (11008 for d = 4096).
  4. LayerNorm vs RMSNorm: what each is invariant to, numerically; cost on CPU.
"""
import math
import time

import numpy as np
import torch

torch.manual_seed(0)
torch.set_num_threads(4)

print("== 1. activations ==")
x = torch.linspace(-6, 6, 120_001, dtype=torch.float64)
g_exact = torch.nn.functional.gelu(x)
g_tanh = torch.nn.functional.gelu(x, approximate="tanh")
print(f"GELU exact vs tanh approximation: max |diff| = {(g_exact - g_tanh).abs().max().item():.2e}")
for v in (-3.0, -1.0, -0.5, 0.5, 2.0):
    t = torch.tensor(v)
    print(f"  x={v:+.1f}: ReLU {torch.relu(t).item():+.4f}  GELU {torch.nn.functional.gelu(t).item():+.4f}  "
          f"SiLU {torch.nn.functional.silu(t).item():+.4f}")
print("GELU/SiLU are smooth and slightly negative below 0, so units don't 'die' the way ReLU units can")

print("\n== 2. signal propagation through 50 ReLU layers (width 512) ==")
print(f"{'init':18s} " + " ".join(f"{'layer ' + str(l):>9}" for l in (1, 10, 25, 50)))
scales = {}
for name, std_fn in (("Xavier  1/sqrt(n)", lambda n: 1 / math.sqrt(n)), ("Kaiming sqrt(2/n)", lambda n: math.sqrt(2 / n))):
    h = torch.randn(1024, 512)
    out = []
    for layer in range(1, 51):
        W = torch.randn(512, 512) * std_fn(512)
        h = torch.relu(h @ W)
        if layer in (1, 10, 25, 50):
            out.append(h.pow(2).mean().sqrt().item())
    scales[name] = out
    print(f"{name:18s} " + " ".join(f"{v:>9.2e}" for v in out))
print("ReLU zeroes half the variance each layer; Kaiming's factor 2 compensates, Xavier's doesn't (vanishing)")
assert scales["Xavier  1/sqrt(n)"][-1] < 1e-3 and 0.3 < scales["Kaiming sqrt(2/n)"][-1] < 3

print("\n== 3. SwiGLU parameter arithmetic ==")
d = 4096
mlp = 2 * d * 4 * d
for name, h in (("exact 8/3 d", 8 * d / 3), ("Llama-2-7B / Llama-1 (rounded up to a multiple of 256)", 256 * math.ceil(8 * d / 3 / 256))):
    print(f"{name:55s} hidden {h:8.1f}: SwiGLU params 3*d*h = {3 * d * h:,.0f} vs GELU MLP 2*d*4d = {mlp:,}")
print("SwiGLU(x) = (SiLU(x W_gate) * (x W_up)) W_down: three matrices, so hidden = 8/3 d keeps the parameter count")

print("\n== 4. LayerNorm vs RMSNorm ==")
D = 1024
xs = torch.randn(8, D, dtype=torch.float64) * 3 + 5
ln = lambda v: (v - v.mean(-1, keepdim=True)) / torch.sqrt(v.var(-1, unbiased=False, keepdim=True) + 1e-6)
rms = lambda v: v / torch.sqrt(v.pow(2).mean(-1, keepdim=True) + 1e-6)
for name, f in (("LayerNorm", ln), ("RMSNorm", rms)):
    shift = (f(xs + 7.0) - f(xs)).abs().max().item()
    scale = (f(xs * 13.0) - f(xs)).abs().max().item()
    print(f"{name:9s}: change after adding a constant 7: {shift:.2e}; after multiplying by 13: {scale:.2e}")
assert (ln(xs + 7) - ln(xs)).abs().max() < 1e-9 and (rms(xs + 7) - rms(xs)).abs().max() > 1e-2
big = torch.randn(4096, 4096)
lnm, rmsn = torch.nn.LayerNorm(4096, elementwise_affine=True), torch.nn.RMSNorm(4096)
for name, m in (("LayerNorm", lnm), ("RMSNorm", rmsn)):
    with torch.no_grad():
        for _ in range(3):
            m(big)
        t0 = time.perf_counter()
        for _ in range(20):
            m(big)
    print(f"{name:9s} on 4096 x 4096 (CPU, 4 threads): {(time.perf_counter() - t0) / 20 * 1e3:.1f} ms (one measured run)")
print(f"parameters per norm layer: LayerNorm {sum(p.numel() for p in lnm.parameters())} (gain + bias), "
      f"RMSNorm {sum(p.numel() for p in rmsn.parameters())} (gain only)")
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except the norm timings, which are one measured run):

```text
== 1. activations ==
GELU exact vs tanh approximation: max |diff| = 4.73e-04
  x=-3.0: ReLU +0.0000  GELU -0.0040  SiLU -0.1423
  x=-1.0: ReLU +0.0000  GELU -0.1587  SiLU -0.2689
  x=-0.5: ReLU +0.0000  GELU -0.1543  SiLU -0.1888
  x=+0.5: ReLU +0.5000  GELU +0.3457  SiLU +0.3112
  x=+2.0: ReLU +2.0000  GELU +1.9545  SiLU +1.7616
GELU/SiLU are smooth and slightly negative below 0, so units don't 'die' the way ReLU units can

== 2. signal propagation through 50 ReLU layers (width 512) ==
init                 layer 1  layer 10  layer 25  layer 50
Xavier  1/sqrt(n)   7.05e-01  2.77e-02  1.29e-04  1.77e-08
Kaiming sqrt(2/n)   9.96e-01  9.88e-01  9.33e-01  6.19e-01
ReLU zeroes half the variance each layer; Kaiming's factor 2 compensates, Xavier's doesn't (vanishing)

== 3. SwiGLU parameter arithmetic ==
exact 8/3 d                                             hidden  10922.7: SwiGLU params 3*d*h = 134,217,728 vs GELU MLP 2*d*4d = 134,217,728
Llama-2-7B / Llama-1 (rounded up to a multiple of 256)  hidden  11008.0: SwiGLU params 3*d*h = 135,266,304 vs GELU MLP 2*d*4d = 134,217,728
SwiGLU(x) = (SiLU(x W_gate) * (x W_up)) W_down: three matrices, so hidden = 8/3 d keeps the parameter count

== 4. LayerNorm vs RMSNorm ==
LayerNorm: change after adding a constant 7: 2.22e-15; after multiplying by 13: 2.45e-07
RMSNorm  : change after adding a constant 7: 1.33e+00; after multiplying by 13: 4.15e-08
LayerNorm on 4096 x 4096 (CPU, 4 threads): 7.2 ms (one measured run)
RMSNorm   on 4096 x 4096 (CPU, 4 threads): 20.9 ms (one measured run)
parameters per norm layer: LayerNorm 8192 (gain + bias), RMSNorm 4096 (gain only)

ALL ASSERTIONS PASSED
```

---

## 4. The Andrew Ng Lens: Debugging Training Is Error Analysis on the Optimizer

### 4.1 Ng's checklist, translated to training failures

Ng's classic advice for neural nets: first get training loss down (bias), then worry about dev loss (variance). When training loss itself won't go down, the error-analysis spreadsheet has different columns: per-layer activation scale, per-layer gradient norm, fraction of dead units, and loss at step 0 vs expected.

| Symptom | Diagnostic | Typical cause |
|---|---|---|
| Initial loss ≠ ln(num_classes) for a fresh classifier | Compare step-0 loss with ln K (5.01 for 150 classes) | Bad init or label bug |
| Loss flat from step 0 | Gradient norms near 0 in early layers | Vanishing signal (Xavier + ReLU at depth), frozen params, LR too small |
| Loss NaN after some steps | Activation or gradient norms exploding | LR too high, missing norm, fp16 overflow (01.3 §1.11) |
| Train loss fine, val bad | Train/val gap | Variance: more data, regularization, smaller model (or a linear head, §1.1) |

### 4.2 The gradient check is your unit test

Before trusting a custom layer, loss or training loop, compare autograd gradients with finite differences (01.3 and 04.2 did this for softmax and InfoNCE), or with a reference implementation (§3.1 vs PyTorch). It's the deep-learning equivalent of a contract test, and it catches sign errors and missing terms that "the loss went down" never will.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | Deep MLP outputs ~0, no learning | Activation RMS falls ~√2 per layer (10⁻⁸ at layer 50) | Xavier init with ReLU | Kaiming init; normalization; residuals | Log per-layer activation scale at step 0 |
| F2 | A "frozen" component still changes | Base weights differ after training | Missing `requires_grad_(False)`, or params passed to the optimizer | Freeze explicitly; pass only trainable params | Assert frozen params' grads are None (01.2 listing) |
| F3 | OOM in training though the model fits for inference | Activation memory | Backward needs stored activations | Gradient checkpointing; smaller micro-batches | Memory budget includes activations × sequence length |
| F4 | Port of a model gives slightly different outputs | Max diff ~1e-3 | GELU tanh vs erf, eps, or norm placement mismatch | Match the config exactly (`hidden_act`, `layer_norm_eps`, pre/post-norm) | Golden-output test against the reference (05.4) |
| F5 | "RMSNorm should be faster" but it's slower | 20.9 vs 7.2 ms on CPU | Unfused RMSNorm vs fused LayerNorm kernel | Use a fused implementation; measure | Benchmark kernels on target hardware |
| F6 | Config hidden sizes "look wrong" (11008) | Ratio ≈ 2.7 instead of 4 | SwiGLU's 8/3 rule, rounded to 256 | Nothing: it's correct | Know the rule when estimating FLOPs and memory |
| F7 | Very deep model unstable early in training | Loss spikes in the first steps | Post-norm at depth without warmup | Pre-norm, warmup, residual scaling | Architecture review for depth > ~24 |
| F8 | Dead units | Many ReLU outputs exactly 0 for all inputs | Large negative bias or LR spike | GELU/SiLU; lower LR; better init | Track the fraction of always-zero units |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Explain backpropagation without saying 'chain rule' first."</b></summary>

**Initial Prompt.** A backend engineer interviewing for an ML-platform role.

**L5 Answer.** "It computes gradients using the chain rule, layer by layer, from the output back to the input."

**Why L5 Fails in Production.** It's correct but mechanical. It doesn't explain why it's efficient, what must be stored, or how to debug it.

**L7 Principal Defense.** "During the forward pass, every operation records its inputs and a local rule: given ∂L/∂output, produce ∂L/∂inputs (a vector–Jacobian product). Backward visits the graph in reverse topological order, applies each rule once, and accumulates into parents. For a matmul C = AB that's G·Bᵀ and Aᵀ·G, so weight gradients are outer products of stored input activations and output deltas. Three consequences: activations must be stored (training memory, checkpointing); total cost is ~2–3× a forward pass for *all* parameters (we measured 2.7× on an 8.4M-parameter MLP, vs 8.4M passes for finite differences); and a parameter off the path to the loss gets no gradient. Our 80-line implementation matches PyTorch to 1e-16."

**Bar-Raiser Follow-ups.**
- *"Why reverse and not forward mode?"* Forward mode costs one pass per *input* direction. With millions of parameters and one scalar loss, reverse mode (one pass per output) wins by orders of magnitude.

</details>

<details><summary><b>Q2 · "Why does Llama use RMSNorm and SwiGLU instead of LayerNorm and GELU?"</b></summary>

**Initial Prompt.** A config-reading question.

**L5 Answer.** "They're newer and work better."

**Why L5 Fails in Production.** It doesn't say what each changes, what it costs, or how to recognize it in a config.

**L7 Principal Defense.** "RMSNorm drops LayerNorm's mean subtraction and bias: it keeps scale invariance (we measured both removing a ×13 scale to ~1e-7) and gives up shift invariance (RMSNorm changes by 1.33 when you add a constant). The re-centring turned out to be unnecessary, and RMSNorm is cheaper, *with a fused kernel*. Unfused on CPU it was 3× slower than fused LayerNorm in our measurement. SwiGLU is a gated FFN: SiLU(xW_gate) ⊙ (xW_up), then W_down. Three matrices instead of two, so the hidden size is 8/3·d to keep parameters equal, which is exactly why Llama-7B's intermediate size is 11008 (8/3 × 4096 rounded up to a multiple of 256). Shazeer showed gated variants beat plain FFNs at equal parameter count."

**Bar-Raiser Follow-ups.**
- *"Where are most parameters in a Llama block?"* The FFN: 3·d·h ≈ 8d² vs attention's 4d² (less with grouped-query attention). About two-thirds of the block.

</details>

<details><summary><b>Q3 · "A 50-layer MLP we built outputs nearly zero and doesn't learn. Why?"</b></summary>

**Initial Prompt.** A custom deep network with ReLU activations and default-ish initialization.

**L5 Answer.** "Use Adam instead of SGD."

**Why L5 Fails in Production.** The optimizer can't fix a signal that has already vanished at initialization.

**L7 Principal Defense.** "Check the forward signal at step 0. With weights ~N(0, 1/n) and ReLU, each layer halves the second moment, so the scale falls about √2 per layer. We measured activation RMS of 1.8e-8 at layer 50 with Xavier vs 0.62 with Kaiming's √(2/n). Gradients vanish the same way. Fix: Kaiming initialization for ReLU-family activations, plus normalization layers and residual connections, which is what transformers rely on. Then confirm with per-layer activation and gradient norms at step 0."

**Bar-Raiser Follow-ups.**
- *"Why does a residual help?"* d(h + f(h))/dh = I + f′(h): an identity path for gradients regardless of depth.

</details>

<details><summary><b>Q4 · "We'll put an MLP head on our frozen embeddings instead of logistic regression; it's more powerful."</b></summary>

**Initial Prompt.** CLINC-style intent routing.

**L5 Answer.** "Yes, MLPs are universal approximators, so they'll do better."

**Why L5 Fails in Production.** Capacity isn't the bottleneck when the encoder already made the classes nearly linearly separable. Measured: MLP head 0.949 vs LR 0.960 validation accuracy.

**L7 Principal Defense.** "The encoder already did the nonlinear work. In its output space, intents are close to linearly separable, so an MLP mainly adds variance and tuning burden: learning rate, schedule, dropout, epochs. Start with LR. It's convex, calibratable, and fast (02.1). Move to an MLP only if error analysis shows systematic non-linear confusions *and* the learning curve says data can support more capacity, and validate with the same eval. The usual better lever is the representation itself (SetFit, an adapter, 04.2)."

**Bar-Raiser Follow-ups.**
- *"When does an MLP head win?"* Mixed inputs (embeddings plus tabular), interactions between features, or many examples per class on a frozen encoder that's a poor fit for the task.

</details>

<details><summary><b>Q5 · "What's the difference between pre-norm and post-norm, and why should an engineer care?"</b></summary>

**Initial Prompt.** Porting a model between frameworks.

**L5 Answer.** "It's where the normalization goes; it doesn't matter much."

**Why L5 Fails in Production.** It matters for correctness when porting, and for stability when training deep models.

**L7 Principal Defense.** "Post-norm, h = Norm(h + F(h)), is used by the original Transformer, BERT and MiniLM. Pre-norm, h = h + F(Norm(h)), is used by GPT-2 onward and Llama. Pre-norm keeps the residual trunk an identity path, so deep stacks train stably, while post-norm normalizes the trunk and needs warmup at depth. For a port, getting it wrong produces plausible-but-different outputs. Our from-weights MiniLM implementation (05.4) uses post-norm, matching Hugging Face to 2.6e-15. Swap the order and it silently diverges. Always validate a port against golden outputs."

**Bar-Raiser Follow-ups.**
- *"Any other port gotchas?"* GELU variant (tanh vs erf), LayerNorm eps (1e-12 in BERT vs 1e-5/1e-6 elsewhere), attention-mask fill values, and position-id offsets.

</details>

<details><summary><b>Q6 · "Estimate the training compute for fine-tuning a 135M-parameter model on 100M tokens."</b></summary>

**Initial Prompt.** Capacity planning.

**L5 Answer.** "Depends on the GPU."

**Why L5 Fails in Production.** The FLOP count doesn't depend on the GPU. Only the time does.

**L7 Principal Defense.** "Forward ≈ 2·params FLOPs per token (one multiply-add per weight). Backward ≈ 2× forward, consistent with our measured 2.7× forward+backward over forward. So training ≈ 6·params·tokens = 6 × 1.35e8 × 1e8 ≈ 8.1e16 FLOPs. At an *achieved* 50 TFLOP/s on a modern accelerator, that's ~27 minutes. On a laptop GPU at a few TFLOP/s, a few hours. Add attention FLOPs for long sequences, and plan memory for activations (or use checkpointing). LoRA cuts the weight-gradient share (01.2 §1.8: ~2/3 of full-FT FLOPs) but not the forward/backward through activations."

**Bar-Raiser Follow-ups.**
- *"Why 'achieved'?"* Real utilization is typically 30–60% of peak. Use a measured MFU for your stack.

</details>

<details><summary><b>Q7 · "GELU exact or tanh approximation: does it matter?"</b></summary>

**Initial Prompt.** Two implementations of the same model disagree slightly.

**L5 Answer.** "They're the same function."

**Why L5 Fails in Production.** They differ by up to 4.7e-4 per activation, which compounds over layers and can flip near-tie predictions or break golden-output tests.

**L7 Principal Defense.** "The model's config states which variant it was trained with (`hidden_act: gelu` = exact erf in Hugging Face BERT; `gelu_new`/`gelu_pytorch_tanh` = tanh). Run the same one. The listing measures a max difference of 4.7e-4 between them. For serving, mismatches show up as small drifts in embeddings, and therefore in thresholds and rankings. So the export path (ONNX, other runtimes) must preserve the exact op. We verified the ONNX export bit-for-bit in task terms (02.3)."

**Bar-Raiser Follow-ups.**
- *"Why did the tanh form exist?"* It was faster on older hardware without fast erf. Modern kernels make the distinction mostly about fidelity.

</details>

<details><summary><b>Q8 · "Your custom loss trains, but results are worse than the paper's. How do you debug it?"</b></summary>

**Initial Prompt.** A new contrastive variant implemented from a paper.

**L5 Answer.** "Tune hyperparameters longer."

**Why L5 Fails in Production.** If the gradient is wrong (a sign, a missing term, a detached tensor), no amount of tuning fixes it, and "the loss goes down" is consistent with a wrong gradient.

**L7 Principal Defense.** "Unit-test the gradient first. Compare autograd against central finite differences on tiny inputs (we did this for softmax CE, InfoNCE and the MLP: errors ~1e-9 to 1e-16), then check against a reference implementation if one exists. Then check the forward on known cases: the loss at a perfect solution should hit its floor, and with random inputs it should be near ln(N). Then look at per-parameter gradient norms for zeros (detached paths). Only then tune."

**Bar-Raiser Follow-ups.**
- *"Finite differences in float32?"* Use float64 for the check, since float32 round-off swamps small perturbations.

</details>

---

## 7. Invariants Checklist

- [ ] Every custom layer or loss has a gradient check (finite differences or a reference) in its test suite.
- [ ] Initialization matches the activation (Kaiming for ReLU-family). Step-0 activation and gradient norms are logged.
- [ ] Frozen components are asserted frozen (no grads, unchanged weights) after training.
- [ ] Model ports match the config exactly (activation variant, norm eps, pre/post-norm) and pass a golden-output test.
- [ ] Kernel-level claims (RMSNorm is faster, etc.) are benchmarked on the target hardware.
- [ ] Training-memory plans include activations, not just weights and optimizer states.
- [ ] Heads on frozen embeddings start linear. MLPs must beat LR on the same eval to ship.

---

## 8. References

1. D. Rumelhart, G. Hinton, R. Williams, *Learning representations by back-propagating errors*, Nature 323, 1986. DOI 10.1038/323533a0.
2. A. Griewank, A. Walther, *Evaluating Derivatives: Principles and Techniques of Algorithmic Differentiation*, SIAM 2008.
3. X. Glorot, Y. Bengio, *Understanding the difficulty of training deep feedforward neural networks*, AISTATS 2010.
4. K. He et al., *Delving Deep into Rectifiers* (Kaiming initialization), ICCV 2015. https://arxiv.org/abs/1502.01852
5. D. Hendrycks, K. Gimpel, *Gaussian Error Linear Units (GELUs)*, 2016. https://arxiv.org/abs/1606.08415
6. N. Shazeer, *GLU Variants Improve Transformer*, 2020. https://arxiv.org/abs/2002.05202
7. J. Ba, J. Kiros, G. Hinton, *Layer Normalization*, 2016. https://arxiv.org/abs/1607.06450
8. B. Zhang, R. Sennrich, *Root Mean Square Layer Normalization*, NeurIPS 2019. https://arxiv.org/abs/1910.07467
9. R. Xiong et al., *On Layer Normalization in the Transformer Architecture* (pre- vs post-norm), ICML 2020. https://arxiv.org/abs/2002.04745
10. H. Touvron et al., *Llama 2: Open Foundation and Fine-Tuned Chat Models*, 2023. https://arxiv.org/abs/2307.09288
11. A. Karpathy, *micrograd* (a tiny scalar autograd engine, the inspiration for §3.1's design). https://github.com/karpathy/micrograd
12. PyTorch, *Autograd mechanics*. https://docs.pytorch.org/docs/stable/notes/autograd.html
