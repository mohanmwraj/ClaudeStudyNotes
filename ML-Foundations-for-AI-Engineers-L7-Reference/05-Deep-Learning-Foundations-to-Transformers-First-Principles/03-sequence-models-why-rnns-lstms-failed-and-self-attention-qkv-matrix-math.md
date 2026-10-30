# 05.3 · Sequence Models: Why RNNs & LSTMs Lost, and Self-Attention's QKV Matrix Math

> **Folder 05 · Deep Learning Foundations to Transformers, from First Principles**
> **Measured on:** PyTorch 2.14.1 (CPU, 4 threads; CUDA on an RTX 3050 Laptop GPU for one timing table), Windows 11. All data is seeded and synthetic.
> **Design sources:** Hochreiter (1991) and Bengio, Simard & Frasconi (1994) on vanishing gradients, Hochreiter & Schmidhuber (LSTM, 1997), Bahdanau et al. (attention, 2015), Vaswani et al. (*Attention Is All You Need*, 2017), Su et al. (RoPE, 2021), Dao et al. (FlashAttention, 2022). Full list in §8.

---

## 0. Orientation: The One-Hop Path

Andrew Ng's framing: **a recurrent network reads a sentence one word at a time and must carry everything it remembers through a single hidden state. Attention lets every word look directly at every other word.** The consequences, all measured in §3:

- **Gradient flow.** In a recurrent net, the gradient that connects the last output to the first input is a product of T Jacobians. At initialization it's **0.000e+00** in float32 by T = 100 for a vanilla RNN, and 8.7e-22 for an LSTM.
- **Memory.** On "repeat the first token after T steps", the RNN fails even at T = 10 (0.254, chance 0.125). The LSTM solves T = 10 (1.000) but not T = 30 within the same training budget. **A one-layer attention model solves T = 100 perfectly (1.000)**, because token 0 is one hop away.
- **Speed is *not* the story at small scale.** One training step at width 128, T = 512: LSTM 136.5 ms vs attention 523.4 ms on CPU, and 14.0 vs 44.6 ms on the laptop GPU. Attention pays for T² scores. Its scaling win comes from having no step-to-step dependency, which lets enormous models train in parallel across accelerators.

Then the matrix math every AI engineer should be able to write on a whiteboard: Q, K, V, the √d_k, heads, causal masks, positions (RoPE), the KV cache that makes generation affordable, and the quadratic cost that makes long context expensive.

### The backend-engineer bridge

| You already know | Sequence-model equivalent |
|---|---|
| A linked list: reach item 0 by walking from item T | **RNN**: information from token 0 must pass through T hidden-state updates |
| A hash map / random access by key | **Attention**: each query scores every key and reads a weighted sum of values |
| A per-connection session cache | **The KV cache**: store each past token's keys/values once, reuse for every new token |
| An O(n²) all-pairs join | **Full attention**: T² scores per head per layer (512 MiB of fp32 scores at T = 4096 for 8 heads) |

### Tier map

| Subtopic | Tier |
|---|---|
| 1.1 RNNs and the vanishing/exploding gradient product | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.2 LSTMs: the additive cell path and its limits | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.3 Attention as a soft, differentiable lookup | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.4 Why divide by √d_k | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.5 Multi-head attention: the reshape | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.6 Causal masking: encoder vs decoder attention | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.7 Positions: permutation equivariance and RoPE | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.8 The KV cache | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.9 The quadratic cost and its workarounds | `[MUST-KNOW: Core AI Engineer Edge]` |
| 1.10 State-space models and linear attention (Mamba, RWKV) | `[GOOD-TO-KNOW: Architectural Literacy]` |
| 1.11 Expressivity theory of transformers | `[SKIP: Academic/Research Only]` |

---

## 1. First-Principles Math & Geometric Intuition

### 1.1 RNNs and the vanishing/exploding gradient product `[MUST-KNOW: Core AI Engineer Edge]`

```text
h_t = tanh(W h_{t−1} + U x_t + b)
∂h_T/∂x_1 = (∏_{t=2..T} ∂h_t/∂h_{t−1}) · ∂h_1/∂x_1 = (∏ diag(1 − h_t²) W) · ∂h_1/∂x_1
```

A product of T matrices behaves like ρᵀ, where ρ is roughly the largest singular value of diag(tanh′)·W. If ρ < 1 it **vanishes** geometrically, and if ρ > 1 it **explodes**. Measured at initialization:

```text
    T  vanilla RNN (tanh)         LSTM
    5           1.712e-01    3.052e-02
   20           1.108e-05    5.072e-05
   50           8.585e-14    2.325e-11
  100           0.000e+00    8.702e-22
```

By T = 100 the vanilla RNN's gradient from the last output to the first input is *exactly zero* in float32. The network literally cannot learn that the first token matters. Gradient clipping (05.2 §1.9) tames the exploding side, and nothing simple fixes the vanishing side.

### 1.2 LSTMs: the additive cell path and its limits `[GOOD-TO-KNOW: Architectural Literacy]`

The LSTM (Hochreiter & Schmidhuber, 1997) adds a cell state updated *additively*:

```text
c_t = f_t ⊙ c_{t−1} + i_t ⊙ g_t            f = forget gate, i = input gate (sigmoids), g = candidate (tanh)
h_t = o_t ⊙ tanh(c_t)
∂c_T/∂c_1 = ∏ f_t        → if training pushes f ≈ 1, the product stays near 1: a "gradient highway"
```

That's the same idea as the residual connection (05.1 §1.8): an identity-like path through time. But it must be *learned* (f ≈ 1 for the right units). At initialization the LSTM's gradients still vanish (8.7e-22 at T = 100), and within our 400-step budget it learned the memory task at T = 10 (accuracy 1.000) but not at T = 30 (0.121, chance level). LSTMs did dominate sequence modelling for two decades (translation, speech). Their limits are this fragile long-range path and the sequential computation.

### 1.3 Attention as a soft, differentiable lookup `[MUST-KNOW: Core AI Engineer Edge]`

```text
Q = X W_Q,  K = X W_K,  V = X W_V                (X: T × d_model; each row a token)
Attention(Q, K, V) = softmax(Q Kᵀ / √d_k) V       (T × T weights, each row sums to 1)
```

Read it as a hash map with soft matching. Each token's **query** is compared (dot product) with every token's **key**. The softmax turns the scores into weights, and the output is the weighted average of **values**. Every output position is one matrix product away from every input position. In the memory task, the last position's query can put all its weight on position 0's key, which is why the one-layer attention model gets **1.000** at T = 10, 30 *and* 100 while both recurrent models fail at 30 and beyond.

```text
         keys (all tokens)
         k₁   k₂   k₃   k₄ ...
   q_T [ 0.97 0.01 0.01 0.01 ]   ← the query for the last position attends to token 1 directly
                                    output_T = Σ_j a_Tj · v_j  ≈ v₁
```

### 1.4 Why divide by √d_k `[MUST-KNOW: Core AI Engineer Edge]`

If query and key entries are independent with unit variance, q·k = Σᵢ qᵢkᵢ has variance d_k. The listing confirms Var(q·k) = 16.4, 63.0, 255.7, 1029.3 for d_k = 16 … 1024. Without scaling, logits grow like √d_k, the softmax saturates to one-hot, and its gradient (01.3 §1.11: diag(p) − ppᵀ) vanishes:

```text
  d_k  Var(q.k)  max weight, unscaled  max weight, scaled  entropy scaled (nats)
   16      16.4                 0.519               0.067                  4.367
 1024    1029.3                 0.941               0.070                  4.359
```

Dividing by √d_k restores unit-variance logits at every head size: the attention entropy stays ~4.36 nats across a 64× range of d_k. It's the same principle as Kaiming initialization (05.1 §1.6): keep activations at unit scale so gradients survive.

### 1.5 Multi-head attention: the reshape `[MUST-KNOW: Core AI Engineer Edge]`

h heads each attend in their own d_model/h-dimensional subspace, and their outputs are concatenated and projected:

```text
Q (B, T, d_model) ─view→ (B, T, h, d_h) ─transpose→ (B, h, T, d_h)       d_h = d_model / h
per head: softmax(Q_h K_hᵀ / √d_h) V_h  → (B, h, T, d_h) ─transpose/reshape→ (B, T, d_model) ─W_O→ output
```

Heads cost no extra parameters (the same W_Q/K/V/O, split into slices), and they let the layer attend to several things at once (syntax, coreference, position). The listing implements it from raw matrices and matches both `nn.MultiheadAttention` (max diff **1.0e-07**) and `F.scaled_dot_product_attention` (**8.9e-08**). Variants you'll see in configs: **multi-query** and **grouped-query attention** (MQA/GQA) share K/V across groups of query heads to shrink the KV cache (Llama-3-8B: 32 query heads, 8 KV heads), and **multi-head latent attention** (DeepSeek) compresses K/V through a low-rank latent (01.2 §1.13).

### 1.6 Causal masking: encoder vs decoder attention `[MUST-KNOW: Core AI Engineer Edge]`

A **decoder** (GPT, Llama) must not see the future when predicting the next token. Add −∞ above the diagonal of the score matrix before the softmax, so position t attends only to positions ≤ t. The listing changes tokens 6–9 and checks the outputs:

```text
after changing positions 6-9: max change at positions 0-5 = 0.0e+00, at 6-9 = 1.43
```

The past is bit-for-bit unaffected. An **encoder** (BERT, MiniLM) uses no causal mask: every token sees the whole input in both directions, which is ideal for understanding a fixed text (classification, retrieval, reranking), but it can't generate left to right. That single mask is the architectural difference behind 05.4's "when to use a small BERT".

### 1.7 Positions: permutation equivariance and RoPE `[MUST-KNOW: Core AI Engineer Edge]`

Attention by itself is a set function. Permute the input tokens and the outputs permute the same way (max diff **1.8e-07**): without positional information, "dog bites man" and "man bites dog" look identical. Positions must be injected:

- **Learned absolute embeddings** (BERT, GPT-2): add a vector per position index. Simple, but it can't extrapolate past the trained length (MiniLM: 512).
- **Rotary position embedding (RoPE, Su et al.)**: rotate each 2-D pair of query/key dimensions by an angle proportional to the position, θᵢ = 10000^(−i/(d/2)). The dot product of a rotated query at position m and a rotated key at position n then depends **only on m − n**:

```text
RoPE: q_5.k_2 = -2.0355878044, q_105.k_102 = -2.0355878044, q_5.k_4 = -4.5423084104 -> depends only on the offset m - n
```

Relative position falls out of the geometry, with no learned position table. RoPE is used by Llama, Mistral, Qwen and most current LLMs. Long-context extensions (position interpolation, NTK/YaRN scaling) adjust its frequencies, which is why a model's `rope_theta` and `max_position_embeddings` matter when you push context length.

### 1.8 The KV cache `[MUST-KNOW: Core AI Engineer Edge]`

When a decoder generates token t, the keys and values of tokens 1 … t−1 are the same as in the previous step (the causal mask guarantees the past doesn't change). Store them, and each new token needs only its own projections plus one query against the cache:

```text
max |incremental - full causal| = 7.7e-07
work for token t: cached ~ t*d (one query vs t cached keys); recompute ~ t*d^2 (re-project all) + t^2*d
```

Incremental decoding with a cache reproduces full causal attention to float precision (7.7e-07), at O(t·d) instead of O(t·d² + t²·d) per new token. The cache is why generation is affordable, and also why it's **memory-bound**. KV-cache bytes per token = 2 (K and V) × layers × KV heads × head_dim × bytes. For Llama-3-70B that's 327,680 bytes per token (the Production AI Engineering KB derives it). Long contexts and many concurrent requests are, at bottom, a KV-cache capacity problem: paging (vLLM), prefix sharing, GQA/MLA and KV quantization all target it.

### 1.9 The quadratic cost and its workarounds `[MUST-KNOW: Core AI Engineer Edge]`

```text
     T  time ms  score matrix (fp32, all heads)
   512      4.5                           8 MiB
  1024     13.0                          32 MiB
  2048     78.4                         128 MiB
  4096    389.5                         512 MiB
```

Doubling T quadruples the score matrix, and the measured time grows ~4–6× per doubling at larger T, as memory traffic starts to dominate. Workarounds:

- **FlashAttention** computes exact attention block by block in fast on-chip memory, with an online softmax (01.3 §1.11's max-subtraction trick, applied incrementally), never materializing the T × T matrix. Same result, far less memory traffic.
- **Sliding-window or local attention** (attend only to the last w tokens) and sparse patterns cut the cost to O(T·w).
- **Retrieval instead of context**: send the right 2,000 tokens rather than 200,000. That's the economic case for the retrieval stack of Folders 01–04.

### 1.10 State-space models and linear attention (Mamba, RWKV) `[GOOD-TO-KNOW: Architectural Literacy]`

Recurrence is back, in better form. Structured state-space models (S4, Mamba) and linear-attention RNNs (RWKV) carry a fixed-size state through time, so generation costs O(1) memory per token (no growing KV cache). They train in parallel using scan or convolution formulations, which avoids the sequential-training bottleneck. They're competitive at some scales, and hybrids (attention layers interleaved with SSM layers) are in production models. The trade-off is lossy compression of the past into a fixed state, which brings back a softer version of §1.1's memory question. Recall-heavy tasks (exact copying, lookup over long context) remain attention's strength.

### 1.11 Expressivity theory of transformers `[SKIP: Academic/Research Only]`

Circuit-complexity characterizations, Turing-completeness results and in-context-learning theory are active research. Production depends on §1.3–1.9: the lookup semantics, scaling, masking, positions, the cache and the cost.

---

## 2. Where It Beats an LLM in Production

This file is the *mechanics* behind LLM serving costs. The engineering payoffs:

| Decision | What the math tells you |
|---|---|
| Long-context prompt vs retrieval | Attention cost grows with T², and the KV cache with T × layers × KV heads. Retrieving the right 2k tokens beats sending 200k on cost and latency |
| Choosing a model for high concurrency | GQA/MQA/MLA models have smaller KV caches per token, so more concurrent requests fit per GPU |
| A small model for sequence tagging (PII spans, entity extraction) | A small encoder with bidirectional attention sees both sides of every token; no generation, no KV cache (05.4) |
| Streaming over long event sequences | State-space models keep O(1) memory per token, where full attention's cache grows |

---

## 3. Production Code Blueprint

### 3.1 Why recurrent networks lost: gradients, memory, and timing

```python
"""rnn_lstm_vs_attention.py - why recurrent networks lost to attention: gradient flow, memory, and parallelism.

  1. Gradient of the final hidden state w.r.t. the FIRST input, as the sequence grows (vanilla RNN vs LSTM at init).
  2. A memory task: output the first token after T random tokens. RNN vs LSTM vs a one-layer attention model.
  3. Wall-clock: a recurrence must run T steps in sequence; attention processes all positions at once.
"""
import time

import torch

torch.manual_seed(0)
torch.set_num_threads(4)
V, H = 8, 64

print("== 1. ||d h_T / d x_1|| at initialization (mean of 20 sequences) ==")
print(f"{'T':>5} {'vanilla RNN (tanh)':>19} {'LSTM':>12}")
gn = {}
for T in (5, 20, 50, 100, 200):
    row = []
    for cell in (torch.nn.RNN(V, H, batch_first=True), torch.nn.LSTM(V, H, batch_first=True)):
        norms = []
        for _ in range(20):
            x = torch.randn(1, T, V, requires_grad=True)
            out, _ = cell(x)
            out[0, -1].sum().backward()
            norms.append(x.grad[0, 0].norm().item())
        row.append(sum(norms) / len(norms))
    gn[T] = row
    print(f"{T:>5} {row[0]:>19.3e} {row[1]:>12.3e}")
print("both decay geometrically at init (the product of T Jacobians); the LSTM's additive cell path is what")
print("TRAINING can open up (forget gate near 1); a vanilla RNN has no such path")


class Recall(torch.nn.Module):
    def __init__(self, kind):
        super().__init__()
        self.kind = kind
        self.emb = torch.nn.Embedding(V, H)
        if kind == "attention":
            self.pos = torch.nn.Embedding(512, H)
            self.att = torch.nn.MultiheadAttention(H, 4, batch_first=True)
        else:
            self.rnn = (torch.nn.RNN if kind == "RNN" else torch.nn.LSTM)(H, H, batch_first=True)
        self.out = torch.nn.Linear(H, V)

    def forward(self, tok):
        e = self.emb(tok)
        if self.kind == "attention":
            e = e + self.pos(torch.arange(tok.shape[1]))
            q = e[:, -1:]                                           # the last position asks: what was token 0?
            h, _ = self.att(q, e, e)
            return self.out(h[:, 0])
        h, _ = self.rnn(e)
        return self.out(h[:, -1])


print("\n== 2. memory task: predict token 0 after T steps (chance 0.125; 400 Adam steps, batch 64) ==")
print(f"{'T':>5} " + " ".join(f"{k:>10}" for k in ("RNN", "LSTM", "attention")))
acc = {}
for T in (10, 30, 100):
    row = []
    for kind in ("RNN", "LSTM", "attention"):
        torch.manual_seed(1)
        m = Recall(kind)
        opt = torch.optim.Adam(m.parameters(), lr=3e-3)
        for _ in range(400):
            tok = torch.randint(0, V, (64, T))
            loss = torch.nn.functional.cross_entropy(m(tok), tok[:, 0])
            opt.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(m.parameters(), 1.0)
            opt.step()
        with torch.no_grad():
            tok = torch.randint(0, V, (2000, T))
            row.append((m(tok).argmax(1) == tok[:, 0]).float().mean().item())
    acc[T] = row
    print(f"{T:>5} " + " ".join(f"{a:>10.3f}" for a in row))
assert acc[100][2] > 0.95 and acc[100][0] < 0.5

print("\n== 3. one training step (forward + backward), batch 32, width 128 (one measured run) ==")
devices = ["cpu"] + (["cuda"] if torch.cuda.is_available() else [])
print(f"{'device':6s} {'T':>5} {'LSTM ms':>9} {'attention ms':>13}")
for dv in devices:
    for T in (128, 512):
        x = torch.randn(32, T, 128, device=dv)
        lstm = torch.nn.LSTM(128, 128, batch_first=True).to(dv)
        att = torch.nn.MultiheadAttention(128, 8, batch_first=True).to(dv)
        row = []
        for f in (lambda: lstm(x)[0].sum().backward(), lambda: att(x, x, x)[0].sum().backward()):
            f()
            if dv == "cuda":
                torch.cuda.synchronize()
            t0 = time.perf_counter()
            for _ in range(5):
                f()
            if dv == "cuda":
                torch.cuda.synchronize()
            row.append((time.perf_counter() - t0) / 5 * 1e3)
        print(f"{dv:6s} {T:>5} {row[0]:>9.1f} {row[1]:>13.1f}")
print("raw speed is NOT attention's win at this size: an LSTM step is cheap, attention pays T^2 scores.")
print("attention's wins are the short gradient path (sections 1-2: every position is one hop from every other)")
print("and no step-to-step dependency, which is what lets very large models train at scale on accelerators.")
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except the timing table, which is one measured run):

```text
== 1. ||d h_T / d x_1|| at initialization (mean of 20 sequences) ==
    T  vanilla RNN (tanh)         LSTM
    5           1.712e-01    3.052e-02
   20           1.108e-05    5.072e-05
   50           8.585e-14    2.325e-11
  100           0.000e+00    8.702e-22
  200           0.000e+00    0.000e+00
both decay geometrically at init (the product of T Jacobians); the LSTM's additive cell path is what
TRAINING can open up (forget gate near 1); a vanilla RNN has no such path

== 2. memory task: predict token 0 after T steps (chance 0.125; 400 Adam steps, batch 64) ==
    T        RNN       LSTM  attention
   10      0.254      1.000      1.000
   30      0.123      0.121      1.000
  100      0.122      0.136      1.000

== 3. one training step (forward + backward), batch 32, width 128 (one measured run) ==
device     T   LSTM ms  attention ms
cpu      128      39.4          42.6
cpu      512     136.5         523.4
cuda     128      21.3          37.4
cuda     512      14.0          44.6
raw speed is NOT attention's win at this size: an LSTM step is cheap, attention pays T^2 scores.
attention's wins are the short gradient path (sections 1-2: every position is one hop from every other)
and no step-to-step dependency, which is what lets very large models train at scale on accelerators.

ALL ASSERTIONS PASSED
```

How to read the timing table: at this width the LSTM *is* faster, and the measurement is reported as it came out. The point of the first two sections stands: attention learned the long-range task that recurrence couldn't, because of the one-hop path, not because of FLOPs.

### 3.2 Self-attention from scratch: scaling, heads, masks, RoPE, KV cache, cost

```python
"""self_attention_from_scratch.py - the QKV matrix math of a transformer layer, verified piece by piece.

  1. Why divide by sqrt(d_k): Var(q.k) grows with d_k, and unscaled softmax rows collapse to one-hot.
  2. Multi-head attention from raw matrices == torch.nn.MultiheadAttention == F.scaled_dot_product_attention.
  3. The causal mask: outputs at position t ignore positions > t.
  4. No positions -> permutation equivariance (a bag of tokens); RoPE makes q_m . k_n depend only on m - n.
  5. KV cache: incremental decoding == full recompute, at O(T) instead of O(T^2) work per new token.
  6. Quadratic cost: time and score-matrix memory as the sequence grows.
"""
import math
import time

import torch
import torch.nn.functional as F

torch.manual_seed(0)
torch.set_num_threads(4)

print("== 1. the sqrt(d_k) scale (128 keys, q and k entries ~ N(0, 1)) ==")
print(f"{'d_k':>5} {'Var(q.k)':>9} {'max weight, unscaled':>21} {'max weight, scaled':>19} {'entropy scaled (nats)':>22}")
for dk in (16, 64, 256, 1024):
    q, k = torch.randn(256, dk), torch.randn(128, dk)
    s = q @ k.T
    p_un, p_sc = torch.softmax(s, -1), torch.softmax(s / math.sqrt(dk), -1)
    ent = -(p_sc * p_sc.clamp_min(1e-30).log()).sum(-1).mean()
    print(f"{dk:>5} {s.var().item():>9.1f} {p_un.max(-1).values.mean().item():>21.3f} {p_sc.max(-1).values.mean().item():>19.3f} {ent.item():>22.3f}")
print(f"(uniform attention over 128 keys has entropy ln 128 = {math.log(128):.3f}; unscaled rows become one-hot -> tiny gradients)")

print("\n== 2. multi-head attention three ways (batch 2, T 10, d_model 64, 8 heads) ==")
B, T, Dm, Hh = 2, 10, 64, 8
dh = Dm // Hh
x = torch.randn(B, T, Dm)
mha = torch.nn.MultiheadAttention(Dm, Hh, batch_first=True)
Wq, Wk, Wv = mha.in_proj_weight.split(Dm)
bq, bk, bv = mha.in_proj_bias.split(Dm)


def heads(z):                                                       # (B, T, Dm) -> (B, H, T, dh)
    return z.view(B, T, Hh, dh).transpose(1, 2)


Q, K, Vv = heads(x @ Wq.T + bq), heads(x @ Wk.T + bk), heads(x @ Wv.T + bv)
A = torch.softmax(Q @ K.transpose(-1, -2) / math.sqrt(dh), -1)     # (B, H, T, T)
ours = (A @ Vv).transpose(1, 2).reshape(B, T, Dm) @ mha.out_proj.weight.T + mha.out_proj.bias
ref, _ = mha(x, x, x)
sdpa = F.scaled_dot_product_attention(Q, K, Vv).transpose(1, 2).reshape(B, T, Dm) @ mha.out_proj.weight.T + mha.out_proj.bias
print(f"max |ours - nn.MultiheadAttention| = {(ours - ref).abs().max().item():.2e}; max |ours - SDPA| = {(ours - sdpa).abs().max().item():.2e}")
assert (ours - ref).abs().max() < 1e-5

print("\n== 3. causal mask ==")
mask = torch.triu(torch.ones(T, T, dtype=torch.bool), 1)
causal = lambda inp: F.scaled_dot_product_attention(heads(inp @ Wq.T), heads(inp @ Wk.T), heads(inp @ Wv.T), is_causal=True)
x2 = x.clone()
x2[:, 6:] = torch.randn(B, T - 6, Dm)                               # change the future (positions 6..9)
d_past = (causal(x)[:, :, :6] - causal(x2)[:, :, :6]).abs().max().item()
d_fut = (causal(x)[:, :, 6:] - causal(x2)[:, :, 6:]).abs().max().item()
print(f"after changing positions 6-9: max change at positions 0-5 = {d_past:.1e}, at 6-9 = {d_fut:.2f}")
assert d_past < 1e-6 < d_fut

print("\n== 4. positions ==")
perm = torch.randperm(T)
out = lambda inp: F.scaled_dot_product_attention(heads(inp @ Wq.T), heads(inp @ Wk.T), heads(inp @ Wv.T))
eq = (out(x)[:, :, perm] - out(x[:, perm])).abs().max().item()
print(f"no positional encoding: attention(permuted x) == permuted attention(x): max diff {eq:.1e} (it is a set function)")


def rope(z, pos, base=10000.0):                                     # rotate dimension pairs by pos * theta_i
    half = z.shape[-1] // 2
    theta = base ** (-torch.arange(half, dtype=torch.float64) / half)
    ang = pos[:, None] * theta[None]
    c, s = torch.cos(ang), torch.sin(ang)
    z1, z2 = z[..., :half], z[..., half:]
    return torch.cat([z1 * c - z2 * s, z1 * s + z2 * c], -1)


qv, kv = torch.randn(64, dtype=torch.float64), torch.randn(64, dtype=torch.float64)
dot = lambda m, n: (rope(qv[None], torch.tensor([float(m)])) @ rope(kv[None], torch.tensor([float(n)])).T).item()
print(f"RoPE: q_5.k_2 = {dot(5, 2):.10f}, q_105.k_102 = {dot(105, 102):.10f}, q_5.k_4 = {dot(5, 4):.10f} "
      f"-> depends only on the offset m - n")
assert abs(dot(5, 2) - dot(105, 102)) < 1e-9 and eq < 1e-5

print("\n== 5. KV cache: 64 decoding steps, one head, d 64 ==")
d = 64
Wq1, Wk1, Wv1 = (torch.randn(d, d) / 8 for _ in range(3))
xs = torch.randn(64, d)
full = torch.softmax((xs @ Wq1) @ (xs @ Wk1).T / 8 + torch.triu(torch.full((64, 64), -1e9), 1), -1) @ (xs @ Wv1)
Kc, Vc, inc = [], [], []
for t in range(64):                                                 # each step: project ONLY the new token
    Kc.append(xs[t] @ Wk1)
    Vc.append(xs[t] @ Wv1)
    q = xs[t] @ Wq1
    w = torch.softmax(torch.stack(Kc) @ q / 8, -1)
    inc.append(w @ torch.stack(Vc))
print(f"max |incremental - full causal| = {(torch.stack(inc) - full).abs().max().item():.1e}")
print(f"work for token t: cached ~ t*d (one query vs t cached keys); recompute ~ t*d^2 (re-project all) + t^2*d")
assert (torch.stack(inc) - full).abs().max() < 1e-4

print("\n== 6. quadratic cost: 8 heads x d_head 64, batch 1 (CPU, one measured run) ==")
print(f"{'T':>6} {'time ms':>8} {'score matrix (fp32, all heads)':>31}")
for Tn in (512, 1024, 2048, 4096):
    q = torch.randn(1, 8, Tn, 64)
    t0 = time.perf_counter()
    for _ in range(3):
        torch.softmax(q @ q.transpose(-1, -2) / 8, -1) @ q
    print(f"{Tn:>6} {(time.perf_counter() - t0) / 3 * 1e3:>8.1f} {8 * Tn * Tn * 4 / 2 ** 20:>27.0f} MiB")
print("doubling T quadruples the score matrix; FlashAttention avoids materializing it (Production AI KB, Folder 01)")
print("\nALL ASSERTIONS PASSED")
```

Output (verified, except the time column of part 6, which is one measured run):

```text
== 1. the sqrt(d_k) scale (128 keys, q and k entries ~ N(0, 1)) ==
  d_k  Var(q.k)  max weight, unscaled  max weight, scaled  entropy scaled (nats)
   16      16.4                 0.519               0.067                  4.367
   64      63.0                 0.751               0.067                  4.370
  256     255.7                 0.894               0.068                  4.370
 1024    1029.3                 0.941               0.070                  4.359
(uniform attention over 128 keys has entropy ln 128 = 4.852; unscaled rows become one-hot -> tiny gradients)

== 2. multi-head attention three ways (batch 2, T 10, d_model 64, 8 heads) ==
max |ours - nn.MultiheadAttention| = 1.04e-07; max |ours - SDPA| = 8.94e-08

== 3. causal mask ==
after changing positions 6-9: max change at positions 0-5 = 0.0e+00, at 6-9 = 1.43

== 4. positions ==
no positional encoding: attention(permuted x) == permuted attention(x): max diff 1.8e-07 (it is a set function)
RoPE: q_5.k_2 = -2.0355878044, q_105.k_102 = -2.0355878044, q_5.k_4 = -4.5423084104 -> depends only on the offset m - n

== 5. KV cache: 64 decoding steps, one head, d 64 ==
max |incremental - full causal| = 7.7e-07
work for token t: cached ~ t*d (one query vs t cached keys); recompute ~ t*d^2 (re-project all) + t^2*d

== 6. quadratic cost: 8 heads x d_head 64, batch 1 (CPU, one measured run) ==
     T  time ms  score matrix (fp32, all heads)
   512      4.5                           8 MiB
  1024     13.0                          32 MiB
  2048     78.4                         128 MiB
  4096    389.5                         512 MiB
doubling T quadruples the score matrix; FlashAttention avoids materializing it (Production AI KB, Folder 01)

ALL ASSERTIONS PASSED
```

---

## 4. The Andrew Ng Lens: Architecture as an Inductive-Bias Decision

### 4.1 Match the inductive bias to the error you see

Ng's guidance on choosing architectures is to look at where the model fails. The memory-task table is a clean example of error analysis driving architecture choice: if errors concentrate on *long-range* dependencies (the answer depends on something far back), recurrence is the bottleneck and attention fixes it. If errors are local, a cheaper architecture may do.

### 4.2 Cost as a first-class metric

Ng's evals-first discipline includes cost and latency. For sequence models, report accuracy *and* tokens processed, KV-cache bytes and latency per request, because a model that is 1 point better but needs 4× the context can be the wrong choice. §1.9's table is the reason long-context features need their own cost evals.

---

## 5. Failure Modes

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | A recurrent model ignores early context | Gradient to early inputs ≈ 0 (0.0 at T = 100) | Vanishing products of Jacobians | Attention, or gated/residual paths | Probe tasks with long-range dependencies |
| F2 | Training loss NaN in an RNN | Exploding gradients | ρ > 1 products | Gradient clipping; smaller LR | Monitor gradient norms |
| F3 | Attention outputs near one-hot, training stalls | Softmax saturation | Missing 1/√d_k or very large logits | Scale scores; check initialization | Unit-test attention entropy at init |
| F4 | A generated token depends on future context (train/serve skew) | Leakage in training | Missing or wrong causal mask | Correct mask (`is_causal=True`) | Test: perturb the future, past outputs unchanged (§3.2) |
| F5 | The model ignores word order | Permutation-equivariant behaviour | Positions not added or not wired in | Positional embeddings / RoPE | Shuffled-input test |
| F6 | Quality collapses beyond the trained length | Long prompts degrade sharply | Absolute positions can't extrapolate; RoPE beyond its trained range | Context-extension methods (RoPE scaling), or retrieval | Evaluate at the context lengths you'll serve |
| F7 | Serving OOMs as concurrency grows | KV-cache memory | 2 × layers × kv_heads × head_dim bytes per token | Paged KV (vLLM), GQA models, KV quantization, shorter contexts | KV-cache capacity planning per model |
| F8 | Latency explodes on long prompts | Prefill cost ∝ T² | Full attention | FlashAttention kernels; chunked prefill; retrieval to cut T | Latency SLOs per prompt-length bucket |
| F9 | Incremental decoding differs from full recompute | Mismatch beyond float noise | Cache bug: wrong positions or stale entries | Golden test: incremental == full (7.7e-07 here) | Run that test in CI for every inference change |

---

## 6. Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why did transformers replace RNNs? Don't just say 'parallelism'."</b></summary>

**Initial Prompt.** A design-history question with production implications.

**L5 Answer.** "Transformers are parallelizable and RNNs are sequential, so transformers are faster."

**Why L5 Fails in Production.** It's incomplete and, at small scale, contradicted by measurement: our one-step training timing at width 128 had the LSTM faster than attention on CPU (136.5 vs 523.4 ms at T = 512) and GPU (14.0 vs 44.6 ms).

**L7 Principal Defense.** "Two reasons, and the first matters more for quality. (1) *Path length*: in an RNN, the gradient between position T and position 1 is a product of T Jacobians, which vanished to exactly 0 in float32 by T = 100 at init. Our memory task showed the consequence: RNN at chance for T ≥ 30, LSTM solved T = 10 but not 30, one-layer attention solved T = 100 perfectly. Attention connects every pair of positions in one hop. (2) *No step-to-step dependency in training*: all positions of a sequence are processed together, which is what lets billion-parameter models train at scale on accelerators, even though attention does more arithmetic (T² scores). The price is quadratic cost and a growing KV cache at inference."

**Bar-Raiser Follow-ups.**
- *"Are RNNs dead?"* No. State-space models and linear-attention RNNs (Mamba, RWKV) bring fixed-size state and O(1)-per-token generation back, trained in parallel. They're weaker at exact long-range recall than attention.

</details>

<details><summary><b>Q2 · "Write attention on the whiteboard and justify every term."</b></summary>

**Initial Prompt.** The classic.

**L5 Answer.** "softmax(QKᵀ/√d)V, where Q, K, V are linear projections."

**Why L5 Fails in Production.** No justification of the √d, the softmax axis, the heads or the mask, and that's where the production bugs live.

**L7 Principal Defense.** "Q = XW_Q, K = XW_K, V = XW_V. QKᵀ scores every query against every key (T × T). Dividing by √d_k keeps logits at unit variance (Var(q·k) = d_k, measured 1029 at d_k = 1024), so the softmax doesn't saturate. The softmax runs over *keys* (each row sums to 1), then multiplies V for a weighted read. Heads split d_model into h subspaces via a reshape, at no extra parameters (matched nn.MultiheadAttention to 1e-7). A decoder adds −∞ above the diagonal: we verified the past is unaffected by future edits. Positions come from RoPE or learned embeddings, since attention alone is permutation-equivariant. Output goes through W_O, then the residual and norm."

**Bar-Raiser Follow-ups.**
- *"What's the memory cost?"* T² scores per head per layer if materialized: 512 MiB fp32 for 8 heads at T = 4096. FlashAttention avoids storing them.

</details>

<details><summary><b>Q3 · "Explain the KV cache and estimate its size for a production model."</b></summary>

**Initial Prompt.** Capacity planning for an LLM serving cluster.

**L5 Answer.** "It caches previous keys and values so generation is faster."

**Why L5 Fails in Production.** It doesn't say why it's correct, what it saves, or how big it gets, and the size is the capacity-planning number.

**L7 Principal Defense.** "With a causal mask, past tokens' keys and values never change, so store them and compute only the new token's projections plus one query against the cache. That's O(t·d) per token instead of O(t·d² + t²·d), and our incremental decoder matched full recompute to 7.7e-07. Size per token = 2 × layers × KV heads × head_dim × bytes. For Llama-3-70B (80 layers, 8 KV heads via GQA, head_dim 128, bf16): 2 × 80 × 8 × 128 × 2 = 327,680 bytes, ~320 KiB per token, so a 32k-token context is ~10 GiB per sequence. Concurrency × context length × that number is the GPU-memory budget, which is why paged KV caches, GQA/MLA and KV quantization exist."

**Bar-Raiser Follow-ups.**
- *"Why is decode memory-bound?"* Each new token reads the whole cache and all weights to do O(1) tokens of compute, so arithmetic intensity is low (the Production AI Engineering KB's roofline analysis).

</details>

<details><summary><b>Q4 · "Why divide by √d_k and not d_k, or nothing?"</b></summary>

**Initial Prompt.** A precise follow-up.

**L5 Answer.** "To normalize the scores."

**Why L5 Fails in Production.** "Normalize" doesn't say *to what*, or what breaks otherwise.

**L7 Principal Defense.** "With unit-variance entries, q·k has variance d_k, so its standard deviation is √d_k. Dividing by √d_k gives unit-variance logits at any head size. Without it, softmax rows saturate: the mean max weight was 0.941 at d_k = 1024 unscaled vs 0.070 scaled. Saturated softmax has vanishing gradients, since its Jacobian diag(p) − ppᵀ → 0 near one-hot. Dividing by d_k would over-shrink (variance 1/d_k), making attention nearly uniform and uninformative. √d_k is the variance-preserving choice, like Kaiming init."

**Bar-Raiser Follow-ups.**
- *"Do models change it?"* Some use a learned or fixed temperature, or QK-norm (normalize q and k) to control logit growth during training. Same goal: keep the softmax out of saturation.

</details>

<details><summary><b>Q5 · "What is RoPE and why do most current LLMs use it?"</b></summary>

**Initial Prompt.** Reading a model config: `rope_theta: 500000`.

**L5 Answer.** "It's a positional encoding."

**Why L5 Fails in Production.** It doesn't say why relative position emerges, or why `rope_theta` matters for long context.

**L7 Principal Defense.** "RoPE rotates each 2-D pair of query and key dimensions by angle position × θᵢ, with θᵢ = base^(−i/(d/2)). Rotations compose, so the dot product of a query rotated by m and a key rotated by n depends only on m − n. We verified q₅·k₂ = q₁₀₅·k₁₀₂ to 10 digits. Relative position comes for free, there's no position table, and attention stays a dot product. The base (`rope_theta`) sets the wavelengths: larger bases (500,000 in Llama 3 vs 10,000 originally) stretch them, which supports longer contexts. Extension methods (position interpolation, NTK/YaRN) rescale frequencies to go beyond the trained length. Evaluate at the lengths you'll serve."

**Bar-Raiser Follow-ups.**
- *"Learned absolute positions?"* They can't extrapolate past the trained maximum (512 in MiniLM), which is why long-context encoders moved to relative schemes.

</details>

<details><summary><b>Q6 · "Users want 200k-token context for document QA. What do you tell them?"</b></summary>

**Initial Prompt.** A product request.

**L5 Answer.** "Use a model with a 200k context window."

**Why L5 Fails in Production.** It works technically, but ignores cost (prefill ∝ T², KV cache ∝ T) and quality (models don't use long context uniformly well).

**L7 Principal Defense.** "Do the arithmetic first. Score memory and prefill grow quadratically (our CPU attention went from 4.5 ms at T = 512 to 390 ms at 4,096 for one layer), and the KV cache grows linearly per request (~320 KiB per token for a 70B-class model, so 200k tokens is ~61 GiB per request). Then measure quality on our documents at those lengths. The usual design is retrieval to select the relevant ~2–8k tokens (Folders 01–04), with long context reserved for tasks that need whole-document reasoning, behind prompt caching so repeated documents don't pay prefill twice."

**Bar-Raiser Follow-ups.**
- *"When is long context the right tool?"* Whole-document tasks (summarize everything, cross-reference sections), small numbers of documents reused across many questions (with caching), or when retrieval recall is provably poor.

</details>

<details><summary><b>Q7 · "How would you test an inference engine's attention implementation?"</b></summary>

**Initial Prompt.** A team writes a custom attention kernel for serving.

**L5 Answer.** "Compare outputs on a few prompts."

**Why L5 Fails in Production.** A few prompts miss masking bugs, cache bugs and numerical edge cases that only show at specific lengths or batch compositions.

**L7 Principal Defense.** "Golden-reference tests, each targeting one property: (1) outputs match a reference SDPA/MHA on random inputs across shapes (we hit 1e-7); (2) causality: perturb future tokens, past outputs unchanged bit-for-bit; (3) incremental decoding with the KV cache equals full recompute (7.7e-07 here); (4) permutation behaviour with positions disabled; (5) RoPE relative-position invariance; (6) padding and masks: padded rows don't affect real ones; (7) batch invariance, if determinism is a requirement (01.3 §1.12). Plus fp16/bf16 tolerances measured against fp32."

**Bar-Raiser Follow-ups.**
- *"Why test batch invariance?"* Kernel reduction orders that change with batch size make outputs differ under load, the Thinking Machines nondeterminism finding.

</details>

<details><summary><b>Q8 · "Mamba-style models claim linear time. Should we switch?"</b></summary>

**Initial Prompt.** A team considers an SSM for long event streams.

**L5 Answer.** "Yes, linear beats quadratic."

**Why L5 Fails in Production.** Asymptotics aren't the whole story. A fixed-size state compresses the past lossily, which hurts exact long-range recall, the very thing attention's one-hop path is good at (§3.1).

**L7 Principal Defense.** "SSMs and linear-attention RNNs keep O(1) memory per token at inference and train in parallel, so they're attractive for very long streams and memory-bound serving. The trade-off is a fixed-size state. Tasks needing exact recall of arbitrary earlier tokens (copying, lookup, 'what was the first token') favour attention, while smooth aggregation tasks suit SSMs. Evaluate on our own sequences for both quality and cost, and consider hybrids (a few attention layers among SSM layers), which recent production models use."

**Bar-Raiser Follow-ups.**
- *"Does this relate to the RNN results here?"* Directly. It's the memory problem again, with much better learned dynamics and training parallelism than the 1990s RNN.

</details>

---

## 7. Invariants Checklist

- [ ] Attention implementations are tested against a reference (values, causality, cache equivalence, padding, RoPE relativity).
- [ ] Every decoder has a causal-mask test (perturb the future → the past is unchanged).
- [ ] Context-length features ship with cost evals (prefill latency, KV bytes per request) and quality evals at the target lengths.
- [ ] KV-cache capacity is planned per model: 2 × layers × KV heads × head_dim × bytes per token.
- [ ] Model choice for high-concurrency serving considers GQA/MQA/MLA KV savings.
- [ ] Architecture claims about speed are measured on the target hardware and sizes, not assumed.
- [ ] Retrieval is the default alternative to brute-force long context.

---

## 8. References

1. Y. Bengio, P. Simard, P. Frasconi, *Learning long-term dependencies with gradient descent is difficult*, IEEE Trans. Neural Networks 5(2), 1994. DOI 10.1109/72.279181.
2. S. Hochreiter, J. Schmidhuber, *Long Short-Term Memory*, Neural Computation 9(8), 1997. DOI 10.1162/neco.1997.9.8.1735.
3. D. Bahdanau, K. Cho, Y. Bengio, *Neural Machine Translation by Jointly Learning to Align and Translate*, ICLR 2015. https://arxiv.org/abs/1409.0473
4. A. Vaswani et al., *Attention Is All You Need*, NeurIPS 2017. https://arxiv.org/abs/1706.03762
5. J. Su et al., *RoFormer: Enhanced Transformer with Rotary Position Embedding*, 2021. https://arxiv.org/abs/2104.09864
6. T. Dao et al., *FlashAttention: Fast and Memory-Efficient Exact Attention with IO-Awareness*, NeurIPS 2022. https://arxiv.org/abs/2205.14135
7. J. Ainslie et al., *GQA: Training Generalized Multi-Query Transformer Models from Multi-Head Checkpoints*, 2023. https://arxiv.org/abs/2305.13245
8. A. Gu, T. Dao, *Mamba: Linear-Time Sequence Modeling with Selective State Spaces*, 2023. https://arxiv.org/abs/2312.00752
9. B. Peng et al., *RWKV: Reinventing RNNs for the Transformer Era*, 2023. https://arxiv.org/abs/2305.13048
10. PyTorch, `torch.nn.functional.scaled_dot_product_attention`. https://docs.pytorch.org/docs/stable/generated/torch.nn.functional.scaled_dot_product_attention.html
11. W. Kwon et al., *Efficient Memory Management for Large Language Model Serving with PagedAttention* (vLLM), SOSP 2023. https://arxiv.org/abs/2309.06180
