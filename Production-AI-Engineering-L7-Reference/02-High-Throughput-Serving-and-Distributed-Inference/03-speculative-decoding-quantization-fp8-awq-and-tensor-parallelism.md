# 03 · Speculative Decoding, Quantization (FP8, AWQ), and Tensor Parallelism

> **Folder:** `02-High-Throughput-Serving-and-Distributed-Inference/` · **File 3 of 3**
> **Anchoring papers:** Leviathan, Kalman & Matias, *Fast Inference from Transformers via Speculative Decoding* (ICML
> 2023) · Chen et al., *Accelerating Large Language Model Decoding with Speculative Sampling* (2023) · Cai et al.,
> *Medusa* (ICML 2024) · Li et al., *EAGLE* (ICML 2024), *EAGLE-2* (EMNLP 2024), *EAGLE-3* (2025) · Gloeckle et al.,
> *Better & Faster LLMs via Multi-token Prediction* (ICML 2024) · DeepSeek-AI, *DeepSeek-V3* (2024; MTP, fine-grained
> FP8) · Micikevicius et al., *FP8 Formats for Deep Learning* (2022) · Dettmers et al., *LLM.int8()* (NeurIPS 2022) ·
> Xiao et al., *SmoothQuant* (ICML 2023) · Frantar et al., *GPTQ* (ICLR 2023) · Lin et al., *AWQ* (MLSys 2024) ·
> Shoeybi et al., *Megatron-LM* (2019) · Korthikanti et al., *Reducing Activation Recomputation in Large Transformer
> Models* (MLSys 2023; sequence parallelism) · OCP *Microscaling (MX) Formats* spec (2023).
> **Code baseline:** Python 3.10+ (CPython 3.14.5 + NumPy 2.5.4) · Java 21 (JDK 25.0.4, `--release 21`). Listings
> import Folder 01's `roofline.py` and File 01's `batching_sim.py`. The Java advisor uses Folder 01's
> `RooflinePlanner`.
> **Previous:** [02 · Disaggregated serving](02-disaggregated-serving-prefill-decode-split-and-kv-cache-rdma.md) ·
> **Next folder:** `03-Vector-DB-Internals-HNSW-DiskANN-and-Hybrid-Index/`

---

## 0. The thesis in one paragraph

Folder 01 left decode with idle tensor cores and saturated HBM. This file covers the three industrial ways to spend
that imbalance:

- **Speculative decoding** spends idle FLOPs. A cheap drafter proposes γ tokens and the target model verifies all of
  them in **one** forward pass. That pass streams the same weight and KV bytes as a single decode step, so accepted
  tokens are almost free. Rejection sampling keeps the output distribution *exactly* the target's.
- **Quantization** cuts bytes. FP8/INT8/INT4 weights and FP8 KV move the memory roof. Done wrong, outlier channels
  destroy accuracy; done right (per-channel and group scales, SmoothQuant, AWQ), 4-bit weights lose little.
- **Tensor parallelism** splits bytes across GPUs, at the cost of two all-reduces per layer. Those all-reduces are
  latency-bound for decode-sized messages and bandwidth-bound for prefill-sized ones.

None of the three is free. Speculation stops paying at high batch, because verification turns compute-bound.
Weight-only INT4 hurts throughput past the GEMM knee. TP beyond $n_{kv}$ or across nodes wastes HBM and adds
milliseconds per step. The closing Java advisor searches all three jointly per SLO tier.

---

## Part A — Speculative decoding

### A.1 The algorithm and its exactness proof

A **target** model $p$ and a cheap **draft** $q$. One round:

1. The draft autoregressively samples $x_1,\dots,x_\gamma \sim q$ (γ cheap steps).
2. The target runs **one** forward pass over the γ+1 positions, yielding $p(\cdot \mid x_{<i})$ for each.
3. Left to right, accept $x_i$ with probability $\min\!\big(1, p(x_i)/q(x_i)\big)$.
4. At the first rejection, sample a replacement from the **residual**
   $r(x) = \dfrac{\max(0,\, p(x) - q(x))}{\sum_y \max(0,\, p(y) - q(y))}$ and stop.
5. If all γ are accepted, sample one bonus token from $p$ at position γ+1.

**Exactness.** Let $\beta = \sum_y \min(p(y), q(y))$. For one position, the probability of emitting $x$ is

$$
\underbrace{q(x)\min\!\Big(1,\tfrac{p(x)}{q(x)}\Big)}_{\text{draft } x \text{ and accept}}
+ \underbrace{(1-\beta)}_{\text{reject}}\cdot\frac{\max(0, p(x)-q(x))}{1-\beta}
= \min(p(x), q(x)) + \max(0, p(x) - q(x)) = p(x),
$$

using $\sum_y \max(0, p - q) = 1 - \beta$. By induction over positions, the emitted sequence is distributed **exactly**
as target sampling. The draft changes only *speed*, never *quality*.

Verified by simulation (§A.6). A toy target/draft pair over a 6-token vocabulary, 60,000 samples of the first 3
tokens:

| Sampler | Total-variation distance from the exact target distribution |
|---------|------------------------------------------------------------:|
| Direct sampling from the target (the noise floor at n = 60,000) | 0.0176 |
| **Speculative sampling (rejection rule)** | **0.0167** (indistinguishable) |
| Naive "accept if draft == target argmax" under sampling | **0.3420** (badly biased) |

The naive rule is a real production bug. It is correct for **greedy** decoding (temperature 0) and silently wrong
for sampling.

### A.2 How many tokens per round

With an i.i.d. per-token acceptance rate $\alpha = \mathbb{E}[\beta] = 1 - \mathrm{TV}(p, q)$, the number of tokens
emitted per target forward is

$$
\mathbb{E}[\text{tokens/round}] = \sum_{k=0}^{\gamma} \alpha^{k} = \frac{1 - \alpha^{\gamma+1}}{1-\alpha},
$$

which the listing confirms against a Bernoulli simulation:

| α \ γ | 1 | 2 | 4 | 8 |
|------:|--:|--:|--:|--:|
| 0.6 | 1.60 | 1.96 | 2.31 | 2.47 |
| 0.8 | 1.80 | 2.44 | 3.36 | 4.33 |
| 0.9 | 1.90 | 2.71 | 4.10 | 6.13 |

There are diminishing returns in γ: at α = 0.6, going from γ = 4 to γ = 8 buys 0.16 tokens. Leviathan et al.'s
wall-time improvement assumes a constant verify cost of one target step:
$\frac{1-\alpha^{\gamma+1}}{(1-\alpha)(\gamma c + 1)}$, where $c$ is the draft-to-target step cost ratio. The next
section shows why that assumption fails at high batch.

### A.3 The roofline reason it works, and why it stops working

Verification scores γ+1 tokens per sequence in one forward pass. The weights are streamed once, and **each sequence's
KV is read once for all γ+1 queries**. While the GEMMs are memory-bound ($B(\gamma+1) \lesssim 300$ tokens on H100),
verifying is nearly as cheap as one decode step. The extra queries also raise attention intensity from $g$ to
$g(\gamma+1)$. Once $B(\gamma+1)$ passes the knee, verification becomes compute-bound and costs grow linearly:

- verify cost at B = 1, γ = 4: **1.01×** a decode step;
- at B = 256: **2.55×**.

Speedup vs batch for Llama-3-70B (8×H100 TP=8, 4K context), from `spec_decoding.py`:

| Batch | Plain step | 1B draft, γ=4, α=.70 | 1B draft, γ=2, α=.70 | head/MTP, γ=1, α=.85 | head/MTP, γ=3, α=.80 |
|------:|-----------:|---------------------:|---------------------:|---------------------:|---------------------:|
| 1 | 8.18 ms | **1.96×** | 1.81× | 1.78× | **2.62×** |
| 8 | 8.70 ms | 1.90× | 1.78× | 1.75× | 2.54× |
| 32 | 10.48 ms | 1.75× | 1.69× | 1.70× | 2.34× |
| 64 | 12.85 ms | 1.47× | 1.62× | 1.65× | 2.09× |
| 128 | 17.61 ms | 1.13× | 1.32× | 1.54× | 1.56× |
| 256 | 27.87 ms | **0.95× (slower)** | 1.12× | 1.29× | 1.29× |

The 1B draft's cost is computed from the roofline for Llama-3.2-1B on the same TP=8 group. "Head/MTP" models an
EAGLE/Medusa/MTP-style drafter costing ~4% of a target step per drafted token. Reading the table:

1. **Speculation is a low-batch / latency tool.** It is worth 2–2.6× at B ≤ 8, and it is a *slowdown* at B = 256 with
   an aggressive γ.
2. **Cheaper drafters and smaller γ degrade more gracefully,** because they waste less compute on rejected tokens when
   compute is the bottleneck.
3. **The optimal γ falls as batch grows.** Production engines adapt γ to load, or switch speculation off above a batch
   threshold.

### A.4 The drafter zoo

| Drafter | How it drafts | Strengths | Costs |
|---------|---------------|-----------|-------|
| Small draft model (same tokenizer) | separate LM | generic; no target training | its own KV cache and weights; α depends on family match |
| **Medusa** | extra decoding heads on the target's last hidden state, tree of candidates | no separate model | trained heads; tree attention; reported 2.2–3.6× (⚠ verify) |
| **EAGLE / EAGLE-2 / EAGLE-3** | a lightweight autoregressive head over target *features*; dynamic draft trees (EAGLE-2); multi-layer feature fusion trained at test-time scale (EAGLE-3) | among the highest acceptance rates for a tiny drafter | per-target training |
| **MTP (DeepSeek-V3)** | the model is *trained* to predict extra tokens with sequential MTP modules; reused as a drafter | reported 85–90% acceptance of the second token, ~1.8× TPS | needs a model trained with MTP |
| n-gram / prompt lookup | copy spans from the prompt or history | free; great for RAG/code edits that echo context | useless for novel text |
| Lookahead / Jacobi | parallel fixed-point iterations | no drafter | more FLOPs per step |

**Tree verification.** Drafters often propose a *tree* of candidates. The target verifies all branches in one pass
with a tree-structured attention mask (each node attends to its ancestors only), then accepts the longest valid path.
More candidates raise expected accepted length and also verify cost, which is again a batch-dependent roofline trade.

### A.5 Production concerns

- **Acceptance rate is a live metric**, per tenant and domain. Code and templated output accept well; creative
  writing accepts poorly. A domain shift can turn speculation into pure overhead.
- **Adaptive control:** lower γ or disable speculation above a batch or load threshold (the §A.3 table). Engines expose
  speculative configs per deployment (⚠ verify the knobs for your version).
- **Memory:** a draft model needs its own weights and KV. Head-style drafters reuse the target's KV.
- **Interaction with structured output:** grammar-constrained decoding must apply the same constraints to draft and
  target distributions, or acceptance collapses.
- **Correctness:** use the rejection rule for any temperature > 0. Greedy verification is valid only at temperature 0.

### A.6 Listing: exactness, acceptance math, and speedup vs batch

```python
"""spec_decoding.py - speculative decoding: exactness proof-by-simulation, the acceptance math, and why
the speedup collapses at high batch (NumPy; uses batching_sim.py + roofline.py from the same directory).

Toy models are first-order Markov chains over a small vocabulary so the exact target distribution of
any continuation can be enumerated and compared with what the sampler actually produces.
"""
from __future__ import annotations

import itertools

import numpy as np

from batching_sim import Chunk, mixed_step_time
from roofline import H100, LLAMA3_70B, LLAMA3_8B, DenseModel

V = 6
LLAMA32_1B = DenseModel("Llama-3.2-1B", 2048, 16, 32, 8, 64, 8192, 128256, tied=True)


def markov(seed: int, temp: float) -> np.ndarray:
    logits = np.random.default_rng(seed).standard_normal((V, V)) / temp
    e = np.exp(logits - logits.max(axis=1, keepdims=True))
    return e / e.sum(axis=1, keepdims=True)


P = markov(1, 0.7)                                       # target  p(next | last)
Q = 0.6 * P + 0.4 * markov(2, 0.7)                       # draft: correlated with the target, not equal


def spec_step(last: int, gamma: int, rng: np.random.Generator, verify: str = "rejection") -> list[int]:
    """One draft+verify round (Leviathan et al. 2023, Algorithm 1). Returns the tokens it emits (1..gamma+1)."""
    drafts, ctx = [], last
    for _ in range(gamma):                                # gamma cheap autoregressive draft steps
        x = int(rng.choice(V, p=Q[ctx]))
        drafts.append(x)
        ctx = x
    out, ctx = [], last
    for x in drafts:                                      # ONE target forward scores all gamma+1 positions
        p, q = P[ctx], Q[ctx]
        if verify == "rejection":
            if rng.random() < min(1.0, p[x] / q[x]):      # accept with prob min(1, p/q)
                out.append(x)
                ctx = x
                continue
            resid = np.maximum(p - q, 0.0)                # on reject: sample norm(max(0, p - q))
            out.append(int(rng.choice(V, p=resid / resid.sum())))
            return out
        # naive: "accept if the draft equals the target's argmax" - fine for greedy, WRONG for sampling
        if x == int(np.argmax(p)):
            out.append(x)
            ctx = x
            continue
        out.append(int(rng.choice(V, p=p)))
        return out
    out.append(int(rng.choice(V, p=P[ctx])))              # all accepted: a bonus token from the target
    return out


def sample_k(start: int, k: int, gamma: int, n: int, seed: int, verify: str) -> np.ndarray:
    rng = np.random.default_rng(seed)
    counts = np.zeros((V,) * k)
    for _ in range(n):
        seq, last = [], start
        while len(seq) < k:
            toks = spec_step(last, gamma, rng, verify)
            seq += toks
            last = toks[-1]
        counts[tuple(seq[:k])] += 1
    return counts / n


def exact_k(start: int, k: int) -> np.ndarray:
    probs = np.zeros((V,) * k)
    for seq in itertools.product(range(V), repeat=k):
        pr, last = 1.0, start
        for x in seq:
            pr *= P[last, x]
            last = x
        probs[seq] = pr
    return probs


def expected_tokens(alpha: float, gamma: int) -> float:
    """E[tokens per target forward] with i.i.d. acceptance rate alpha (Leviathan eq. 1)."""
    return (1 - alpha ** (gamma + 1)) / (1 - alpha)


def target_decode_s(b: int, ctx: int) -> float:
    return mixed_step_time(LLAMA3_70B, H100, 8, b, b * ctx)


def verify_s(b: int, ctx: int, gamma: int) -> float:
    """Score gamma+1 positions per sequence in one forward: GEMMs see b*(gamma+1) tokens, KV is read once."""
    return mixed_step_time(LLAMA3_70B, H100, 8, 0, 0, [Chunk(gamma + 1, ctx)] * b, sample_rows=b * (gamma + 1))


def speedup(b: int, ctx: int, gamma: int, alpha: float, draft_step_s: float) -> float:
    plain = 1.0 / target_decode_s(b, ctx)                         # tokens/s per sequence without speculation
    spec = expected_tokens(alpha, gamma) / (gamma * draft_step_s + verify_s(b, ctx, gamma))
    return spec / plain


def main() -> None:
    alpha_rows = np.minimum(P, Q).sum(axis=1)                     # alpha(state) = sum_x min(p, q) = 1 - TV
    print(f"toy target/draft over V={V}: per-state acceptance alpha = {np.round(alpha_rows, 3)}")

    exact = exact_k(0, 3)
    rng0 = np.random.default_rng(6)
    direct = np.zeros((V,) * 3)
    for _ in range(60_000):                                       # the same n drawn straight from the target
        a = int(rng0.choice(V, p=P[0]))
        b = int(rng0.choice(V, p=P[a]))
        direct[a, b, int(rng0.choice(V, p=P[b]))] += 1
    floor = 0.5 * np.abs(direct / 60_000 - exact).sum()
    print(f"  first 3 tokens, direct target sampling (noise floor at n=60,000): TV = {floor:.4f}")
    for verify in ("rejection", "naive-argmax"):
        emp = sample_k(0, 3, gamma=3, n=60_000, seed=5, verify=verify)
        tv = 0.5 * np.abs(emp - exact).sum()
        print(f"  first 3 tokens, {verify:13s}: total-variation distance from the target = {tv:.4f}")
        if verify == "rejection":
            assert tv < 1.5 * floor + 0.005, "speculative sampling must be indistinguishable from the target"
        else:
            assert tv > 0.05, "argmax verification under sampling is biased"

    rng = np.random.default_rng(9)
    for a in (0.6, 0.8, 0.9):
        for g in (1, 3, 5):
            sim = np.mean([1 + next((i for i in range(g) if rng.random() >= a), g) for _ in range(40_000)])
            assert abs(sim - expected_tokens(a, g)) < 0.03
    print("  E[tokens/verify] = (1 - a^(g+1)) / (1 - a) matches a Bernoulli simulation (a in .6/.8/.9, g in 1/3/5)")
    print("  " + "  ".join(f"a={a}: " + "/".join(f"{expected_tokens(a, g):.2f}" for g in (1, 2, 4, 8))
                           for a in (0.6, 0.8, 0.9)) + "   (g = 1/2/4/8)")

    ctx = 4096
    draft_1b = lambda b: mixed_step_time(LLAMA32_1B, H100, 8, b, b * ctx)        # noqa: E731
    head = lambda b: 0.04 * target_decode_s(b, ctx)                             # noqa: E731
    print(f"\n== Speedup vs batch: Llama-3-70B target, 8xH100 TP=8, ctx {ctx} ==")
    print(f"{'batch':>5} {'plain ms':>8} " + " ".join(f"{h:>22s}" for h in
          ("1B draft g=4 a=.70", "1B draft g=2 a=.70", "head/MTP g=1 a=.85", "head/MTP g=3 a=.80")))
    rows = {}
    for b in (1, 8, 32, 64, 128, 256):
        cells = [speedup(b, ctx, 4, 0.70, draft_1b(b)), speedup(b, ctx, 2, 0.70, draft_1b(b)),
                 speedup(b, ctx, 1, 0.85, head(b)), speedup(b, ctx, 3, 0.80, head(b))]
        rows[b] = cells
        print(f"{b:5d} {target_decode_s(b, ctx) * 1e3:8.2f} " + " ".join(f"{c:21.2f}x" for c in cells))
    assert rows[1][0] > 1.5 and rows[256][0] < rows[1][0] and rows[256][0] < 1.15
    print(f"\n  verify cost at B=1: g=4 costs {verify_s(1, ctx, 4) / target_decode_s(1, ctx):.2f}x one decode step; "
          f"at B=256: {verify_s(256, ctx, 4) / target_decode_s(256, ctx):.2f}x")
    _ = LLAMA3_8B
    print("\nall speculative decoding self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified):

```text
toy target/draft over V=6: per-state acceptance alpha = [0.828 0.866 0.835 0.815 0.689 0.817]
  first 3 tokens, direct target sampling (noise floor at n=60,000): TV = 0.0176
  first 3 tokens, rejection    : total-variation distance from the target = 0.0167
  first 3 tokens, naive-argmax : total-variation distance from the target = 0.3420
  E[tokens/verify] = (1 - a^(g+1)) / (1 - a) matches a Bernoulli simulation (a in .6/.8/.9, g in 1/3/5)
  a=0.6: 1.60/1.96/2.31/2.47  a=0.8: 1.80/2.44/3.36/4.33  a=0.9: 1.90/2.71/4.10/6.13   (g = 1/2/4/8)

== Speedup vs batch: Llama-3-70B target, 8xH100 TP=8, ctx 4096 ==
batch plain ms     1B draft g=4 a=.70     1B draft g=2 a=.70     head/MTP g=1 a=.85     head/MTP g=3 a=.80
    1     8.18                  1.96x                  1.81x                  1.78x                  2.62x
    8     8.70                  1.90x                  1.78x                  1.75x                  2.54x
   32    10.48                  1.75x                  1.69x                  1.70x                  2.34x
   64    12.85                  1.47x                  1.62x                  1.65x                  2.09x
  128    17.61                  1.13x                  1.32x                  1.54x                  1.56x
  256    27.87                  0.95x                  1.12x                  1.29x                  1.29x

  verify cost at B=1: g=4 costs 1.01x one decode step; at B=256: 2.55x

all speculative decoding self-checks passed
```

---

## Part B — Quantization

### B.1 The formats, bit by bit

| Format | Sign/exp/mantissa | Bias | Max | Min normal | Min subnormal | Specials |
|--------|------------------:|-----:|----:|-----------:|--------------:|----------|
| **FP8 E4M3 (FN)** | 1/4/3 | 7 | **448** | 2⁻⁶ = 0.015625 | 2⁻⁹ ≈ 0.00195 | no ∞; NaN = S.1111.111; saturate on overflow |
| **FP8 E5M2** | 1/5/2 | 15 | **57,344** | 2⁻¹⁴ ≈ 6.1e-5 | 2⁻¹⁶ ≈ 1.5e-5 | IEEE-style ∞/NaN |
| INT8 (symmetric) | uniform, 255 levels | — | 127·s | — | — | none |
| INT4 (asymmetric + zero point) | uniform, 16 levels | — | 15·s | — | — | none |
| MXFP4 / MXFP8 (OCP) | E2M1 / E4M3·E5M2 elements | — | — | — | — | one shared **E8M0** scale per 32 elements |
| NVFP4 (Blackwell) | E2M1 elements | — | 6 × scale | — | — | **E4M3 scale per 16 elements** + FP32 per-tensor scale |

The listing builds both FP8 grids from the bit definitions: 126 positive finite values for E4M3 and 123 for E5M2. It
asserts max, min-subnormal, round-to-nearest-**even** ties (1.0625 → 1.0, 1.1875 → 1.25), and saturation (1e6 → 448).

**Floats vs integers.** INT grids are uniform, so their *absolute* error is constant and their *relative* error
explodes for small values. FP grids are logarithmic, so their *relative* error is roughly constant (≤ 2⁻⁴ for 3
mantissa bits) across a huge range. That one fact explains the tables below.

### B.2 Weight-only quantization

Synthetic 1024×1024 weights with a realistic per-output-channel scale spread (lognormal σ = 0.5):

| Scheme | Bits/weight (with scales) | Weight rel. error | Output rel. error |
|--------|--------------------------:|------------------:|------------------:|
| INT8 per-tensor | 8.00 | 0.0308 | 0.0302 |
| **INT8 per-channel** | 8.02 | **0.0079** | **0.0078** |
| FP8 E4M3 per-tensor | 8.00 | 0.0265 | 0.0263 |
| FP8 E4M3 per-channel | 8.02 | 0.0265 | 0.0271 |
| INT4 asym per-channel | 4.03 | 0.1260 | 0.1251 |
| **INT4 asym group-128** | 4.25 | 0.1007 | 0.0992 |

Lessons:

1. **Per-channel scales are mandatory for integer formats** (4× less error for INT8). They barely matter for FP8,
   whose relative precision is scale-invariant.
2. **For well-behaved weights, INT8 per-channel is *more accurate* than FP8.** A uniform grid fits a Gaussian
   channel's bulk better than a float grid that spends codes on tiny values. FP8's advantages are **dynamic range**
   (activations, §B.3) and **native Hopper/Blackwell tensor-core throughput** (2× BF16 FLOPs), not precision.
3. **Group-wise scales** (one scale/zero per 128 weights) are what make 4-bit viable, at 0.25 bits/weight of overhead.

### B.3 Activations: outliers, SmoothQuant, and FP8's range

LLM activations develop a few **outlier channels** with magnitudes 10–100× the rest (Dettmers et al. observed them
emerging around the 6.7B scale). Under per-tensor INT8, one outlier channel sets the scale and crushes every other
channel into a few levels. Same weights, activations with 8 channels scaled ×40:

| W8A8 scheme | Output rel. error |
|-------------|------------------:|
| INT8 activations per-tensor (static) | **0.0971** |
| INT8 activations per-token (dynamic) | 0.0458 |
| **SmoothQuant (α = 0.5) + INT8 per-tensor** | **0.0191** |
| FP8 E4M3 activations per-tensor, weights per-channel | 0.0383 |
| FP8 E4M3 activations per-token, weights per-channel | 0.0338 |

**SmoothQuant** migrates difficulty from activations to weights with a per-input-channel scale:

$$
Y = XW^{\top} = (X\,\mathrm{diag}(s)^{-1})\,(W\,\mathrm{diag}(s))^{\top},\qquad
s_j = \frac{\max|X_{:,j}|^{\alpha}}{\max|W_{:,j}|^{1-\alpha}} .
$$

The $\mathrm{diag}(s)^{-1}$ folds into the preceding LayerNorm/RMSNorm weight offline, so it costs nothing at
runtime. Activations become easy to quantize and weights absorb a tolerable increase. Error drops 5× vs per-tensor
INT8. FP8 handles outliers better than per-tensor INT8 through dynamic range alone (0.038 vs 0.097), which is why
**FP8 W8A8 with per-token dynamic activation scales** is the pragmatic Hopper default. DeepSeek-V3 goes finer:
**1×128 tile-wise** activation scales and **128×128 block-wise** weight scales, which makes FP8 viable even for
training.

### B.4 AWQ: protect the weights that matter

AWQ's observation: a small fraction of weight channels are **salient**, namely those multiplied by large activations,
and their quantization error dominates the output error. Instead of keeping them in higher precision (a mixed
format, bad for kernels), scale them up before quantization so they get relatively finer steps, and fold the inverse
scale into the previous op:

$$
s = \bar{|X|}^{\,\alpha}\ \text{(per input channel, normalized)},\qquad
\alpha^{*} = \arg\min_{\alpha \in [0,1]} \big\| Q(W\,\mathrm{diag}(s))\,(\mathrm{diag}(s)^{-1}X^{\top}) - WX^{\top} \big\| .
$$

| INT4 group-128 | Calibration error | Held-out error |
|----------------|------------------:|---------------:|
| Round-to-nearest | 0.0995 | 0.0990 |
| **AWQ (α* = 0.35)** | **0.0497** | **0.0494** (−50%) |

The reduction holds on unseen tokens, because salience is a property of *channels*, not of the calibration
samples. **GPTQ** takes a different route. It quantizes weights column by column and uses second-order (Hessian)
information from calibration data to update the remaining columns, compensating each column's error. GPTQ and AWQ
are the two dominant W4A16 recipes, and both rely on calibration data that should match the production domain.

### B.5 Bytes, capacity, and the roofline

| Llama-3-70B weights | Size | Min H100s for weights | What that leaves |
|---------------------|-----:|----------------------:|-----------------|
| BF16 | 141.1 GB | 2 | TP=2 leaves only ~16K tokens of KV (§C.5): unusable |
| FP8 + per-channel scales | 70.7 GB | 1 | a single H100 (76.4 GB usable at 0.9) has ~6 GB left before activations: no useful KV. Use TP≥2 |
| INT4 g128 + scale/zero | 37.5 GB | 1 | ~35 GB of KV on one H100: a real single-GPU deployment |

Link to the roofline (Folder 01, F4):

- **W4A16** moves the GEMM knee from ~318 to ~80 tokens. It wins at low batch and pays dequantization ALU work at high
  batch.
- **W8A8-FP8** halves bytes *and* doubles the compute roof, so it wins in both regimes.
- **FP8 KV** halves the attention bytes that dominate long-context decode.

### B.6 Listing: the quantization lab

```python
"""quantization_lab.py - FP8 / INT8 / INT4 quantization from the bit patterns up (NumPy).

* exact FP8 E4M3 ("FN": no inf, max 448) and E5M2 grids with round-to-nearest-even and saturation;
* weight-only schemes (per-tensor, per-channel, group-128 asymmetric INT4) on channel-scaled weights;
* W8A8 with LLM-style activation outlier channels: per-tensor vs per-token vs SmoothQuant vs FP8;
* AWQ's activation-aware scale search for W4 g128, checked on held-out activations.
Synthetic tensors stand in for a real checkpoint; the mechanisms, not the absolute numbers, are the point.
"""
from __future__ import annotations

import numpy as np


def fp8_positive_grid(exp_bits: int, man_bits: int, bias: int, fn: bool) -> np.ndarray:
    """All non-negative finite values. fn=True: the E4M3FN convention (top exponent is finite except
    the all-ones mantissa, which is NaN). fn=False: IEEE-like (top exponent = inf/NaN)."""
    vals = [0.0] + [m / 2 ** man_bits * 2.0 ** (1 - bias) for m in range(1, 2 ** man_bits)]   # subnormals
    top = 2 ** exp_bits - 1
    for e in range(1, top + 1):
        if e == top and not fn:
            break
        for m in range(2 ** man_bits):
            if fn and e == top and m == 2 ** man_bits - 1:
                continue
            vals.append((1 + m / 2 ** man_bits) * 2.0 ** (e - bias))
    return np.array(vals)


E4M3 = fp8_positive_grid(4, 3, 7, fn=True)
E5M2 = fp8_positive_grid(5, 2, 15, fn=False)


def to_grid(x: np.ndarray, grid: np.ndarray) -> np.ndarray:
    """Round |x| to the nearest grid value, ties to even mantissa (= even grid index), saturating."""
    a = np.minimum(np.abs(x), grid[-1])
    hi = np.clip(np.searchsorted(grid, a), 1, len(grid) - 1)
    lo = hi - 1
    dlo, dhi = a - grid[lo], grid[hi] - a
    pick = np.where(dlo < dhi, lo, np.where(dhi < dlo, hi, np.where(lo % 2 == 0, lo, hi)))
    return np.sign(x) * grid[pick]


def fp8(x: np.ndarray, axis: int | None = None) -> np.ndarray:
    amax = np.abs(x).max(axis=axis, keepdims=axis is not None)
    s = amax / E4M3[-1]
    return to_grid(x / s, E4M3) * s


def int8_sym(x: np.ndarray, axis: int | None = None) -> np.ndarray:
    amax = np.abs(x).max(axis=axis, keepdims=axis is not None)
    s = amax / 127.0
    return np.clip(np.round(x / s), -127, 127) * s


def int4_asym_groups(w: np.ndarray, group: int) -> np.ndarray:
    """GPTQ/AWQ-style: per (row, group of `group` input columns) scale and zero point, 4-bit codes."""
    out_f, in_f = w.shape
    g = w.reshape(out_f, in_f // group, group)
    lo, hi = g.min(axis=2, keepdims=True), g.max(axis=2, keepdims=True)
    scale = np.maximum(hi - lo, 1e-12) / 15.0
    zp = np.round(-lo / scale)
    q = np.clip(np.round(g / scale) + zp, 0, 15)
    return ((q - zp) * scale).reshape(out_f, in_f)


def rel(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.linalg.norm(a - b) / np.linalg.norm(b))


def make_tensors(seed: int, tokens: int = 512, d_in: int = 1024, d_out: int = 1024):
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((d_out, d_in)) * 0.02
    w *= np.exp(rng.normal(0.0, 0.5, size=(d_out, 1)))         # per-output-channel scale spread
    x = rng.standard_normal((tokens, d_in))
    outliers = rng.choice(d_in, 8, replace=False)                # "emergent" activation channels
    x[:, outliers] *= 40.0
    return w, x, outliers


def awq_search(w: np.ndarray, x_cal: np.ndarray, group: int = 128):
    """Grid-search alpha in s = mean|x|^alpha (normalized) to minimize W4 output error on calibration data.
    The 1/s factor is folded into the previous op (RMSNorm weight / previous linear), so it is free."""
    y = x_cal @ w.T
    act = np.abs(x_cal).mean(axis=0)
    best = (rel(x_cal @ int4_asym_groups(w, group).T, y), 0.0, np.ones_like(act))
    for alpha in np.linspace(0.05, 1.0, 20):
        s = act ** alpha
        s = s / np.sqrt(s.max() * s.min())
        err = rel((x_cal / s) @ int4_asym_groups(w * s, group).T, y)
        if err < best[0]:
            best = (err, float(alpha), s)
    return best


def main() -> None:
    print("== FP8 formats (positive finite grids) ==")
    for name, g in (("E4M3 (FN)", E4M3), ("E5M2", E5M2)):
        print(f"  {name:9s}: {len(g) - 1:3d} positive finite values, max {g[-1]:g}, min subnormal {g[1]:.6g}, "
              f"min normal {g[2 ** (3 if name.startswith('E4') else 2)]:.6g}")
    assert E4M3[-1] == 448 and E4M3[1] == 2 ** -9 and len(E4M3) == 127
    assert E5M2[-1] == 57344 and E5M2[1] == 2 ** -16
    assert to_grid(np.array([1.0625]), E4M3)[0] == 1.0                     # tie -> even mantissa (1.000)
    assert to_grid(np.array([1.1875]), E4M3)[0] == 1.25                    # tie -> even mantissa (1.010)
    assert to_grid(np.array([1e6]), E4M3)[0] == 448                        # saturate, never inf

    w, x, outliers = make_tensors(0)
    y = x @ w.T
    print("\n== Weight-only quantization (activations exact), W 1024x1024 with per-channel scale spread ==")
    schemes = {
        "INT8 per-tensor": (lambda m: int8_sym(m), 8 + 16 / m_size(w)),
        "INT8 per-channel": (lambda m: int8_sym(m, axis=1), 8 + 16 / w.shape[1]),
        "FP8 E4M3 per-tensor": (lambda m: fp8(m), 8 + 16 / m_size(w)),
        "FP8 E4M3 per-channel": (lambda m: fp8(m, axis=1), 8 + 16 / w.shape[1]),
        "INT4 asym per-channel": (lambda m: int4_asym_groups(m, m.shape[1]), 4 + 32 / w.shape[1]),
        "INT4 asym group-128": (lambda m: int4_asym_groups(m, 128), 4 + 32 / 128),
    }
    errs = {}
    for name, (fn, bits) in schemes.items():
        wq = fn(w)
        errs[name] = rel(x @ wq.T, y)
        print(f"  {name:22s} {bits:5.2f} bits/weight   weight rel err {rel(wq, w):.4f}   output rel err {errs[name]:.4f}")
    assert errs["INT8 per-channel"] < errs["INT8 per-tensor"]
    assert errs["INT4 asym group-128"] < errs["INT4 asym per-channel"]

    print(f"\n== W8A8 with {len(outliers)} activation outlier channels (x40) ==")
    wq8 = int8_sym(w, axis=1)
    rows = {
        "INT8 act per-tensor": rel(int8_sym(x) @ wq8.T, y),
        "INT8 act per-token": rel(int8_sym(x, axis=1) @ wq8.T, y),
    }
    alpha = 0.5
    s = np.abs(x).max(axis=0) ** alpha / np.abs(w).max(axis=0) ** (1 - alpha)   # SmoothQuant migration
    rows["SmoothQuant a=0.5 + INT8 per-tensor"] = rel(int8_sym(x / s) @ int8_sym(w * s, axis=1).T, y)
    rows["FP8 E4M3 act per-tensor, W per-chan"] = rel(fp8(x) @ fp8(w, axis=1).T, y)
    rows["FP8 E4M3 act per-token, W per-chan"] = rel(fp8(x, axis=1) @ fp8(w, axis=1).T, y)
    for name, e in rows.items():
        print(f"  {name:38s} output rel err {e:.4f}")
    assert rows["SmoothQuant a=0.5 + INT8 per-tensor"] < rows["INT8 act per-tensor"] / 3
    assert rows["FP8 E4M3 act per-tensor, W per-chan"] < rows["INT8 act per-tensor"]

    print("\n== AWQ (activation-aware scaling) for INT4 group-128 ==")
    x_cal = x[:256]
    awq_cal, best_alpha, s = awq_search(w, x_cal)
    rtn_cal = rel(x_cal @ int4_asym_groups(w, 128).T, x_cal @ w.T)
    x_hold = np.random.default_rng(1).standard_normal((512, w.shape[1]))   # unseen tokens, same channels
    x_hold[:, outliers] *= 40.0
    y_hold = x_hold @ w.T
    rtn_hold = rel(x_hold @ int4_asym_groups(w, 128).T, y_hold)
    awq_hold = rel((x_hold / s) @ int4_asym_groups(w * s, 128).T, y_hold)
    print(f"  round-to-nearest:       calibration {rtn_cal:.4f}, held-out {rtn_hold:.4f}")
    print(f"  AWQ best alpha={best_alpha:.2f}: calibration {awq_cal:.4f}, held-out {awq_hold:.4f} "
          f"({(1 - awq_hold / rtn_hold):.0%} lower error on unseen tokens)")
    assert awq_hold < rtn_hold * 0.9 and awq_cal < rtn_cal

    print("\n== Llama-3-70B weight bytes by format (70.55B params) ==")
    for name, bits in (("BF16", 16), ("FP8 + per-channel scales", 8.016), ("INT4 g128 + scale/zero", 4.25)):
        gb = 70.553e9 * bits / 8 / 1e9
        print(f"  {name:26s} {gb:6.1f} GB  -> min H100s for weights alone: {int(np.ceil(gb / 79.1 / 1.073741824))}")
    print("\nall quantization self-checks passed")


def m_size(m: np.ndarray) -> int:
    return m.size


if __name__ == "__main__":
    main()
```

Output (verified, deterministic):

```text
== FP8 formats (positive finite grids) ==
  E4M3 (FN): 126 positive finite values, max 448, min subnormal 0.00195312, min normal 0.015625
  E5M2     : 123 positive finite values, max 57344, min subnormal 1.52588e-05, min normal 6.10352e-05

== Weight-only quantization (activations exact), W 1024x1024 with per-channel scale spread ==
  INT8 per-tensor         8.00 bits/weight   weight rel err 0.0308   output rel err 0.0302
  INT8 per-channel        8.02 bits/weight   weight rel err 0.0079   output rel err 0.0078
  FP8 E4M3 per-tensor     8.00 bits/weight   weight rel err 0.0265   output rel err 0.0263
  FP8 E4M3 per-channel    8.02 bits/weight   weight rel err 0.0265   output rel err 0.0271
  INT4 asym per-channel   4.03 bits/weight   weight rel err 0.1260   output rel err 0.1251
  INT4 asym group-128     4.25 bits/weight   weight rel err 0.1007   output rel err 0.0992

== W8A8 with 8 activation outlier channels (x40) ==
  INT8 act per-tensor                    output rel err 0.0971
  INT8 act per-token                     output rel err 0.0458
  SmoothQuant a=0.5 + INT8 per-tensor    output rel err 0.0191
  FP8 E4M3 act per-tensor, W per-chan    output rel err 0.0383
  FP8 E4M3 act per-token, W per-chan     output rel err 0.0338

== AWQ (activation-aware scaling) for INT4 group-128 ==
  round-to-nearest:       calibration 0.0995, held-out 0.0990
  AWQ best alpha=0.35: calibration 0.0497, held-out 0.0494 (50% lower error on unseen tokens)

== Llama-3-70B weight bytes by format (70.55B params) ==
  BF16                        141.1 GB  -> min H100s for weights alone: 2
  FP8 + per-channel scales     70.7 GB  -> min H100s for weights alone: 1
  INT4 g128 + scale/zero       37.5 GB  -> min H100s for weights alone: 1

all quantization self-checks passed
```

---

## Part C — Tensor parallelism

### C.1 Megatron sharding: two all-reduces per layer, nothing in between

For a SwiGLU MLP, $Y = (\mathrm{SiLU}(XW_g^\top) \odot XW_u^\top)\,W_d^\top$:

- **Column-parallel** $W_g, W_u$ (split the $d_{ff}$ output dimension): each rank computes its slice of the
  intermediate activation with **no communication**. SiLU and ⊙ are elementwise, so they stay local.
- **Row-parallel** $W_d$ (split its $d_{ff}$ input dimension): each rank produces a **partial sum** of the full
  output.
- **One all-reduce** sums the partials.

Attention is the same: QKV is column-parallel **by heads**, attention runs per head locally, O-projection is
row-parallel, and one all-reduce follows. That gives 2 all-reduces per layer, 160 per Llama-3-70B step. The listing
executes this rank by rank and matches the unsharded result to ~1e-15. Each rank's partial alone is off by O(1),
which shows the all-reduce is load-bearing. For GQA with $TP > n_{kv}$, each rank needs a KV head it shares with
another rank, so **KV heads are replicated** (verified at TP=4 with $n_{kv}$ = 2).

### C.2 Ring all-reduce

Split the buffer of $S$ elements into $n$ chunks. A **reduce-scatter** runs $n-1$ steps (each rank sends one chunk to
its neighbor, which adds it), and then each rank owns one fully reduced chunk. An **all-gather** runs $n-1$ more steps.

$$
\text{bytes sent per rank} = 2\,\frac{n-1}{n}\,S,\qquad
t_{\text{AR}} \approx \alpha_{\text{call}} + 2\frac{n-1}{n}\frac{S}{\text{busbw}}.
$$

Per-rank traffic is **bandwidth-optimal and independent of $n$** (verified: 1,750 elements sent per rank for
$n=8, S=1000$). A naive gather-to-root puts $2(n-1)S$ = 14,000 on the root's link instead. On NVSwitch systems, NCCL
can also use **NVLink SHARP (NVLS)**, which reduces in the switch and roughly halves the data each GPU injects
(⚠ verify availability per platform and NCCL version).

### C.3 Sequence parallelism

Between the row-parallel output and the next column-parallel input sit norms and residual adds, which are replicated
on every rank under plain TP. **Sequence parallelism** replaces the all-reduce with a **reduce-scatter along the
sequence dimension**. Each rank normalizes $1/n$ of the tokens, and an **all-gather** runs before the next
column-parallel GEMM. Total bytes are the same as an all-reduce (RS + AG), and the activations of norms and dropout
are sharded $n$-ways. The listing verifies RS → RMSNorm(shard) → AG equals AR → RMSNorm exactly.

### C.4 Latency-bound decode, bandwidth-bound prefill

One all-reduce of a [tokens × 8192] BF16 activation ($\alpha$ = 10 µs per NCCL call on NVLink, 25 µs cross-node;
busbw 360 GB/s on NVLink, 45 GB/s per GPU on 400G IB):

| Tokens in step | Message | TP=2 NVLink | TP=4 NVLink | TP=8 NVLink | TP=16 cross-node IB |
|---------------:|--------:|------------:|------------:|------------:|--------------------:|
| 1 | 16 KiB | 10.0 µs | 10.1 µs | 10.1 µs | 25.7 µs |
| 64 | 1 MiB | 12.9 µs | 14.4 µs | 15.1 µs | 68.7 µs |
| 256 | 4 MiB | 21.7 µs | 27.5 µs | 30.4 µs | 199.8 µs |
| 8,192 | 128 MiB | 382.8 µs | 569.2 µs | 662.4 µs | **5,617 µs** |

- **Decode messages are latency-bound.** Below the ~2 MiB crossover ($\alpha \cdot \text{busbw}/(2(n-1)/n)$), per-call
  latency dominates. That is why engines ship custom one-shot/two-shot all-reduce kernels for small messages and fuse
  collectives into GEMM epilogues.
- **Prefill messages are bandwidth-bound,** and they benefit from compute–communication overlap.
- **Crossing the node boundary is catastrophic for decode:** 11.0 ms of all-reduce per step at TP=16 vs 2.4 ms at TP=8
  for Llama-3-70B at B=64. Use pipeline parallelism (cheap point-to-point between stages) or more replicas across
  nodes, never TP.

### C.5 Choosing the TP degree (Llama-3-70B decode, B=64, 4K context)

| TP | Weights per GPU | KV capacity | Fits 64 × 4K? | Step | TP comm | tok/s/GPU |
|---:|----------------:|------------:|:-------------:|-----:|--------:|----------:|
| 2 | 70.6 GB | 16,272 tokens | **no** | 35.90 ms | 2.07 ms | (891) |
| 4 | 35.3 GB | 463,162 | yes | 19.26 ms | 2.30 ms | 831 |
| 8 | 17.6 GB | 1,356,942 | yes | 10.95 ms | 2.42 ms | 731 |

At a *fixed* batch, TP=4 wins per GPU, because less of each step is all-reduce and fixed overhead. But TP=8 holds
2.9× the KV, so under an SLO it runs much larger batches. Folder 01 measured 1,456 vs 1,137 tok/s/GPU at a 30 ms ITL,
in favor of TP=8. **Always compare TP degrees at the SLO, not at a fixed batch.**

### C.6 The parallelism menu for inference

| Strategy | Splits | Per-layer communication | Good for | Bad for |
|----------|--------|------------------------|----------|---------|
| **TP** | weights within layers | 2 all-reduces (latency-bound at decode) | per-token latency; fitting a model in one node | crossing nodes; $TP > n_{kv}$ (KV replication); MLA (latent replication) |
| **PP** | layers into stages | point-to-point activation per stage boundary | spanning nodes cheaply; very large models | per-token latency (sum of stages); needs many in-flight microbatches |
| **EP** | MoE experts across GPUs | all-to-all dispatch + combine per MoE layer | MoE with many experts (DeepSeek: wide EP) | load imbalance (hot experts), all-to-all latency |
| **DP attention** | sequences across GPUs (attention only) | boundary to EP/TP MLP layers | MLA models (no latent replication) | small batches per rank |
| **Context parallel** | the sequence itself (ring attention) | KV blocks circulate | very long prefill | decode (little to split) |
| **DP replicas** | nothing; whole copies | none | scaling throughput once a replica fits | memory efficiency (weights duplicated) |

### C.7 Listing: TP, ring all-reduce, sequence parallelism, cost model

```python
"""tensor_parallel_ref.py - Megatron tensor parallelism and ring all-reduce, executed rank by rank (NumPy).

* SwiGLU MLP: column-parallel gate/up + row-parallel down = ONE all-reduce, no communication in between;
* GQA attention: heads sharded by rank (KV heads replicated when tp > n_kv), row-parallel o_proj;
* ring all-reduce = reduce-scatter + all-gather, with per-rank traffic 2(n-1)/n * S, vs a naive
  gather-to-root;
* sequence parallelism: reduce-scatter -> norm on a sequence shard -> all-gather equals all-reduce -> norm;
* an alpha-beta cost model of TP collectives, and TP-degree trade-offs from roofline.py (same directory).
"""
from __future__ import annotations

import numpy as np

from roofline import H100, LLAMA3_70B, decode_step, kv_capacity_tokens


def silu(x: np.ndarray) -> np.ndarray:
    return x / (1.0 + np.exp(-x))


def ring_all_reduce(bufs: list[np.ndarray]) -> tuple[list[np.ndarray], int, int]:
    """Returns (per-rank results, elements sent per rank, steps). Every send in a step happens 'at once'."""
    n, shape = len(bufs), bufs[0].shape
    chunks = [np.array_split(b.astype(np.float64).ravel().copy(), n) for b in bufs]
    sent, steps = 0, 0
    for s in range(n - 1):                                      # reduce-scatter
        msgs = [(r, (r - s) % n, chunks[r][(r - s) % n].copy()) for r in range(n)]
        for r, c, data in msgs:
            chunks[(r + 1) % n][c] += data
        sent += len(msgs[0][2])
        steps += 1
    for s in range(n - 1):                                      # all-gather (rank r owns chunk (r+1) % n)
        msgs = [(r, (r + 1 - s) % n, chunks[r][(r + 1 - s) % n].copy()) for r in range(n)]
        for r, c, data in msgs:
            chunks[(r + 1) % n][c] = data
        sent += len(msgs[0][2])
        steps += 1
    return [np.concatenate(ch).reshape(shape) for ch in chunks], sent, steps


def naive_all_reduce_root_traffic(n: int, size: int) -> int:
    """Gather-to-root then broadcast: the root's link carries 2(n-1)S elements."""
    return 2 * (n - 1) * size


def mlp_ref(x, wg, wu, wd):
    return (silu(x @ wg.T) * (x @ wu.T)) @ wd.T


def mlp_tp(x, wg, wu, wd, tp):
    shards = np.array_split(np.arange(wg.shape[0]), tp)        # split the d_ff dimension
    partials = [(silu(x @ wg[s].T) * (x @ wu[s].T)) @ wd[:, s].T for s in shards]   # [tokens, d] each
    out, _, _ = ring_all_reduce(partials)
    return out[0], partials


def attn_ref(x, wq, wk, wv, wo, n_h, n_kv, d_h):
    t = x.shape[0]
    q = (x @ wq.T).reshape(t, n_h, d_h)
    k = (x @ wk.T).reshape(t, n_kv, d_h)
    v = (x @ wv.T).reshape(t, n_kv, d_h)
    g = n_h // n_kv
    mask = np.triu(np.ones((t, t), dtype=bool), 1)
    heads = []
    for h in range(n_h):
        s = q[:, h] @ k[:, h // g].T / np.sqrt(d_h)
        s[mask] = -np.inf
        p = np.exp(s - s.max(axis=1, keepdims=True))
        heads.append((p / p.sum(axis=1, keepdims=True)) @ v[:, h // g])
    return np.concatenate(heads, axis=1) @ wo.T


def attn_tp(x, wq, wk, wv, wo, n_h, n_kv, d_h, tp):
    """Rank r owns query heads [r*n_h/tp, ...) and the KV heads they need; o_proj is row-parallel."""
    hq = n_h // tp
    partials = []
    for r in range(tp):
        qh = list(range(r * hq, (r + 1) * hq))
        kvh = sorted({h // (n_h // n_kv) for h in qh})          # replicated when tp > n_kv
        rows = lambda heads: np.concatenate([np.arange(h * d_h, (h + 1) * d_h) for h in heads])  # noqa: E731
        q_r, kv_r = rows(qh), rows(kvh)
        local = attn_ref(x, wq[q_r], wk[kv_r], wv[kv_r], np.eye(hq * d_h), hq, len(kvh), d_h)
        partials.append(local @ wo[:, q_r].T)
    out, _, _ = ring_all_reduce(partials)
    return out[0]


def rms_norm(x, w, eps=1e-6):
    return x / np.sqrt((x * x).mean(axis=-1, keepdims=True) + eps) * w


def allreduce_s(nbytes: float, n: int, busbw: float, alpha: float) -> float:
    return 0.0 if n == 1 else alpha + 2.0 * (n - 1) / n * nbytes / busbw


def main() -> None:
    rng = np.random.default_rng(0)
    tokens, d, ff = 16, 64, 256
    x = rng.standard_normal((tokens, d))
    wg, wu, wd = (rng.standard_normal(s) * 0.1 for s in ((ff, d), (ff, d), (d, ff)))
    ref = mlp_ref(x, wg, wu, wd)
    for tp in (2, 4, 8):
        out, partials = mlp_tp(x, wg, wu, wd, tp)
        print(f"MLP TP={tp}: max|err| vs unsharded {np.abs(out - ref).max():.1e}; "
              f"each rank's partial alone is off by {np.abs(partials[0] - ref).max():.2f} (needs the all-reduce)")
        assert np.abs(out - ref).max() < 1e-12

    n_h, n_kv, d_h = 8, 2, 8
    wq = rng.standard_normal((n_h * d_h, d)) * 0.1
    wk = rng.standard_normal((n_kv * d_h, d)) * 0.1
    wv = rng.standard_normal((n_kv * d_h, d)) * 0.1
    wo = rng.standard_normal((d, n_h * d_h)) * 0.1
    aref = attn_ref(x, wq, wk, wv, wo, n_h, n_kv, d_h)
    for tp in (2, 4):
        err = np.abs(attn_tp(x, wq, wk, wv, wo, n_h, n_kv, d_h, tp) - aref).max()
        print(f"GQA attention n_h={n_h} n_kv={n_kv} TP={tp}: max|err| {err:.1e}"
              f"{'  (KV heads replicated 2x)' if tp > n_kv else ''}")
        assert err < 1e-12

    bufs = [rng.standard_normal(1000) for _ in range(8)]
    res, sent, steps = ring_all_reduce(bufs)
    total = np.sum(bufs, axis=0)
    assert all(np.abs(r - total).max() < 1e-12 for r in res)
    print(f"ring all-reduce n=8, S=1000: {steps} steps, {sent} elements sent per rank "
          f"(= 2(n-1)/n*S = {2 * 7 / 8 * 1000:.0f}); naive gather-to-root puts "
          f"{naive_all_reduce_root_traffic(8, 1000):,} on the root's link")
    assert sent == 2 * 7 * 125

    tp = 4
    partials = [rng.standard_normal((tokens, d)) for _ in range(tp)]
    w_norm = rng.standard_normal(d)
    full = rms_norm(np.sum(partials, axis=0), w_norm)
    shards = np.array_split(np.sum(partials, axis=0), tp, axis=0)     # reduce-scatter along the sequence
    sp = np.concatenate([rms_norm(s, w_norm) for s in shards], axis=0)  # norm on 1/tp of the tokens, then all-gather
    assert np.abs(sp - full).max() < 1e-12
    print(f"sequence parallelism TP={tp}: RS -> RMSNorm(shard) -> AG == AR -> RMSNorm (max|err| "
          f"{np.abs(sp - full).max():.1e}); norm activations per rank {tokens // tp}x{d} instead of {tokens}x{d}")

    print("\n== TP collective cost: one all-reduce of a [tokens x 8192] BF16 activation ==")
    links = {"NVLink, TP=2": (2, 360e9, 10e-6), "NVLink, TP=4": (4, 360e9, 10e-6), "NVLink, TP=8": (8, 360e9, 10e-6),
             "cross-node IB, TP=16": (16, 45e9, 25e-6)}
    print(f"{'tokens':>7} {'bytes':>9} " + " ".join(f"{k:>21s}" for k in links))
    for tok in (1, 64, 256, 8192):
        nbytes = tok * 8192 * 2
        cells = [allreduce_s(nbytes, n, bw, a) * 1e6 for n, bw, a in links.values()]
        print(f"{tok:7d} {nbytes / 2**20:8.2f}M " + " ".join(f"{c:18.1f} us" for c in cells))
    s_star = 10e-6 * 360e9 / (2 * 7 / 8)
    print(f"latency/bandwidth crossover on NVLink TP=8: {s_star / 2**20:.2f} MiB "
          f"(decode messages are latency-bound; prefill messages bandwidth-bound)")
    per_step_tp16 = 2 * 80 * allreduce_s(64 * 8192 * 2, 16, 45e9, 25e-6)
    print(f"Llama-3-70B decode B=64 at TP=16 across nodes: {per_step_tp16 * 1e3:.1f} ms of all-reduce per step "
          f"(vs {2 * 80 * allreduce_s(64 * 8192 * 2, 8, 360e9, 10e-6) * 1e3:.1f} ms at TP=8 on NVLink)")

    print("\n== TP degree for Llama-3-70B decode on H100 (B=64, ctx 4096, BF16) ==")
    for t in (2, 4, 8):
        cap = kv_capacity_tokens(LLAMA3_70B, H100, t)
        e = decode_step(LLAMA3_70B, H100, t, 64, 4096)
        fits = cap >= 64 * 4096
        print(f"  TP={t}: weights {LLAMA3_70B.total_params * 2 / t / 1e9:5.1f} GB/GPU, KV capacity {cap:>9,} tokens "
              f"({'fits' if fits else 'DOES NOT FIT'} 64x4K), step {e.total_s * 1e3:5.2f} ms "
              f"(comm {e.comm_s * 1e3:4.2f}), {64 / e.total_s / t:6,.0f} tok/s/GPU")
    print("\nall tensor-parallel self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified, deterministic):

```text
MLP TP=2: max|err| vs unsharded 1.3e-15; each rank's partial alone is off by 1.36 (needs the all-reduce)
MLP TP=4: max|err| vs unsharded 1.2e-15; each rank's partial alone is off by 1.96 (needs the all-reduce)
MLP TP=8: max|err| vs unsharded 1.3e-15; each rank's partial alone is off by 2.08 (needs the all-reduce)
GQA attention n_h=8 n_kv=2 TP=2: max|err| 3.9e-16
GQA attention n_h=8 n_kv=2 TP=4: max|err| 3.3e-16  (KV heads replicated 2x)
ring all-reduce n=8, S=1000: 14 steps, 1750 elements sent per rank (= 2(n-1)/n*S = 1750); naive gather-to-root puts 14,000 on the root's link
sequence parallelism TP=4: RS -> RMSNorm(shard) -> AG == AR -> RMSNorm (max|err| 0.0e+00); norm activations per rank 4x64 instead of 16x64

== TP collective cost: one all-reduce of a [tokens x 8192] BF16 activation ==
 tokens     bytes          NVLink, TP=2          NVLink, TP=4          NVLink, TP=8  cross-node IB, TP=16
      1     0.02M               10.0 us               10.1 us               10.1 us               25.7 us
     64     1.00M               12.9 us               14.4 us               15.1 us               68.7 us
    256     4.00M               21.7 us               27.5 us               30.4 us              199.8 us
   8192   128.00M              382.8 us              569.2 us              662.4 us             5617.4 us
latency/bandwidth crossover on NVLink TP=8: 1.96 MiB (decode messages are latency-bound; prefill messages bandwidth-bound)
Llama-3-70B decode B=64 at TP=16 across nodes: 11.0 ms of all-reduce per step (vs 2.4 ms at TP=8 on NVLink)

== TP degree for Llama-3-70B decode on H100 (B=64, ctx 4096, BF16) ==
  TP=2: weights  70.6 GB/GPU, KV capacity    16,272 tokens (DOES NOT FIT 64x4K), step 35.90 ms (comm 2.07),    891 tok/s/GPU
  TP=4: weights  35.3 GB/GPU, KV capacity   463,162 tokens (fits 64x4K), step 19.26 ms (comm 2.30),    831 tok/s/GPU
  TP=8: weights  17.6 GB/GPU, KV capacity 1,356,942 tokens (fits 64x4K), step 10.95 ms (comm 2.42),    731 tok/s/GPU

all tensor-parallel self-checks passed
```

---

## Part D — Putting it together: the deployment advisor (Java 21)

A platform control plane has to choose, per model and SLO tier, TP degree × weight format × KV format × speculation.
That is 72 combinations per model here. Picking by intuition is how fleets end up 3× over-provisioned.
`DeploymentAdvisor` searches them with the Folder 01 roofline (derated to 60% MFU / 85% MBU):

- INT4 W4A16 dequantization is modeled as a 1.3× compute penalty (an assumption).
- Speculation uses the expected-tokens formula with verify cost from the roofline.
- The BF16, no-speculation, ideal-efficiency path is **asserted identical** to Folder 01's `RooflinePlanner`: 23.4337
  ms vs 23.4337 ms.

```java
// DeploymentAdvisor.java - Java 21 deployment planner for a model-serving control plane. Searches tensor-parallel
// degree x weight format (BF16 / FP8 W8A8 / INT4 W4A16) x KV format x speculative decoding for each SLO tier,
// using the per-kernel roofline from Folder 01. Its BF16, no-speculation, ideal-efficiency path is asserted to
// equal RooflinePlanner.decodeStep exactly.
// Build & self-test:  javac --release 21 -Xlint:all -Werror -d out RooflinePlanner.java DeploymentAdvisor.java
//                     java -ea -cp out dev.l7.ai.inference.DeploymentAdvisor
package dev.l7.ai.inference;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;

import dev.l7.ai.inference.RooflinePlanner.DenseModel;
import dev.l7.ai.inference.RooflinePlanner.Dtype;
import dev.l7.ai.inference.RooflinePlanner.Gpu;

public final class DeploymentAdvisor {

    private DeploymentAdvisor() {}

    /** bytesPerParam includes scale/zero-point overhead; computePenalty models INT4 dequantization ALU work. */
    public enum WeightFormat {
        BF16(2.0, Dtype.BF16, 1.0), FP8_W8A8(1.0, Dtype.FP8, 1.0), INT4_W4A16(0.53125, Dtype.BF16, 1.3);

        final double bytesPerParam;
        final Dtype compute;
        final double computePenalty;

        WeightFormat(double bytesPerParam, Dtype compute, double computePenalty) {
            this.bytesPerParam = bytesPerParam;
            this.compute = compute;
            this.computePenalty = computePenalty;
        }
    }

    public enum KvFormat {
        BF16(2), FP8(1);

        final int bytes;

        KvFormat(int bytes) { this.bytes = bytes; }
    }

    /** gamma draft tokens per round, acceptance rate alpha, draft cost per drafted token as a fraction of a
     *  plain target decode step (small draft model ~0.1, EAGLE/MTP head ~0.04). */
    public record Speculation(String name, int gamma, double alpha, double draftCostRatio) {
        static final Speculation NONE = new Speculation("none", 0, 0.0, 0.0);

        double expectedTokens() {
            return gamma == 0 ? 1.0 : (1 - Math.pow(alpha, gamma + 1)) / (1 - alpha);
        }
    }

    public record Config(int tp, WeightFormat weights, KvFormat kv, Speculation spec) {
        @Override
        public String toString() {
            return "TP=" + tp + " W=" + weights + " KV=" + kv + " spec=" + spec.name();
        }
    }

    public record Slo(String name, double tpotSeconds, long contextTokens) {}

    public record Estimate(Config config, int batch, double tpotSeconds, double tokPerSecPerGpu, long kvCapacity) {}

    static final double MFU = 0.6, MBU = 0.85;

    private static double kernel(double flops, double bytes, Gpu g, Dtype d, double penalty, double mfu, double mbu) {
        return Math.max(flops / (g.peak(d) * mfu) * penalty, bytes / (g.hbmBw() * mbu));
    }

    private static double gemm(long m, long k, long n, int count, WeightFormat w, Gpu g, double mfu, double mbu) {
        double flops = count * 2.0 * m * k * n;
        double bytes = count * (2.0 * m * k + w.bytesPerParam * k * n + 2.0 * m * n);
        return kernel(flops, bytes, g, w.compute, w.computePenalty, mfu, mbu);
    }

    private static double allReduce(Gpu g, int tp, double bytes) {
        return tp == 1 ? 0.0 : g.arLatency() + 2.0 * (tp - 1) / tp * bytes / g.arBusBw();
    }

    /** One forward over `batch` sequences, each scoring (gamma+1) query tokens against `ctx` cached tokens. */
    static double stepSeconds(DenseModel md, Gpu g, Config c, int batch, long ctx, int queryTokens,
                              double mfu, double mbu) {
        long m = (long) batch * queryTokens;
        int tp = c.tp(), layers = md.nLayers();
        int qOut = md.nHeads() * md.headDim() / tp;
        int kvOut = 2 * md.kvHeadsPerRank(tp) * md.headDim();
        WeightFormat w = c.weights();
        double t = gemm(m, md.dModel(), qOut + kvOut, layers, w, g, mfu, mbu)
                + gemm(m, (long) md.nHeads() * md.headDim() / tp, md.dModel(), layers, w, g, mfu, mbu)
                + gemm(m, md.dModel(), 2L * md.dFf() / tp, layers, w, g, mfu, mbu)
                + gemm(m, md.dFf() / tp, md.dModel(), layers, w, g, mfu, mbu)
                + gemm(m, md.dModel(), md.vocab() / tp, 1, w, g, mfu, mbu);
        double attnFlops = (double) queryTokens * 4.0 * layers * (md.nHeads() / tp) * md.headDim() * ctx * batch;
        double attnBytes = (double) batch * ctx * 2 * layers * md.kvHeadsPerRank(tp) * md.headDim() * c.kv().bytes;
        t += kernel(attnFlops, attnBytes, g, Dtype.BF16, 1.0, mfu, mbu);   // KV read once for all query tokens
        return t + 2.0 * layers * allReduce(g, tp, (double) m * md.dModel() * 2);
    }

    static long kvCapacity(DenseModel md, Gpu g, Config c) {
        double free = g.hbmBytes() * 0.9 - md.totalParams() * c.weights().bytesPerParam / c.tp() - 3 * RooflinePlanner.GIB;
        long perToken = 2L * md.nLayers() * md.kvHeadsPerRank(c.tp()) * md.headDim() * c.kv().bytes;
        return Math.max(0L, (long) Math.floor(free / perToken));
    }

    /** Effective TPOT for a batch: (gamma drafts + one verify) / expected tokens per round. */
    static double tpot(DenseModel md, Gpu g, Config c, int batch, long ctx) {
        Speculation s = c.spec();
        if (s.gamma() == 0) return stepSeconds(md, g, c, batch, ctx, 1, MFU, MBU);
        double plain = stepSeconds(md, g, c, batch, ctx, 1, MFU, MBU);
        double verify = stepSeconds(md, g, c, batch, ctx, s.gamma() + 1, MFU, MBU);
        return (s.gamma() * s.draftCostRatio() * plain + verify) / s.expectedTokens();
    }

    static Optional<Estimate> evaluate(DenseModel md, Gpu g, Config c, Slo slo) {
        long cap = kvCapacity(md, g, c);
        int best = 0;
        double bestTpot = 0;
        for (int b = 1; (long) b * slo.contextTokens() <= cap && b <= 2048; b++) {
            double t = tpot(md, g, c, b, slo.contextTokens());
            if (t > slo.tpotSeconds()) break;
            best = b;
            bestTpot = t;
        }
        if (best == 0) return Optional.empty();
        return Optional.of(new Estimate(c, best, bestTpot, best / bestTpot / c.tp(), cap));
    }

    static List<Estimate> recommend(DenseModel md, Gpu g, Slo slo, List<Speculation> specs) {
        List<Estimate> out = new ArrayList<>();
        for (int tp : new int[] {1, 2, 4, 8}) {
            for (WeightFormat w : WeightFormat.values()) {
                for (KvFormat kv : KvFormat.values()) {
                    for (Speculation s : specs) {
                        evaluate(md, g, new Config(tp, w, kv, s), slo).ifPresent(out::add);
                    }
                }
            }
        }
        out.sort(Comparator.comparingDouble(Estimate::tokPerSecPerGpu).reversed());
        return out;
    }

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) {
        DenseModel md = RooflinePlanner.LLAMA3_70B;
        Gpu h100 = RooflinePlanner.H100;
        Config bf16 = new Config(8, WeightFormat.BF16, KvFormat.BF16, Speculation.NONE);
        double mine = stepSeconds(md, h100, bf16, 256, 4096, 1, 1.0, 1.0);
        double folder01 = RooflinePlanner.decodeStep(md, h100, 8, 256, 256L * 4096).totalSeconds();
        System.out.printf("cross-check vs Folder 01 RooflinePlanner: %.4f ms vs %.4f ms%n", mine * 1e3, folder01 * 1e3);
        check(Math.abs(mine - folder01) < 1e-12, "identical physics");
        check(kvCapacity(md, h100, bf16) == RooflinePlanner.kvCapacityTokens(md, h100, 8, 0.9, 3 * RooflinePlanner.GIB),
                "identical capacity");

        List<Speculation> specs = List.of(Speculation.NONE,
                new Speculation("draft-1B g=3 a=.70", 3, 0.70, 0.12),
                new Speculation("MTP/EAGLE g=1 a=.85", 1, 0.85, 0.04));
        List<Slo> slos = List.of(new Slo("interactive TPOT<=20ms @4K", 0.020, 4096),
                new Slo("standard TPOT<=50ms @4K", 0.050, 4096),
                new Slo("long-context TPOT<=40ms @32K", 0.040, 32_768),
                new Slo("offline TPOT<=200ms @4K", 0.200, 4096));
        for (Slo slo : slos) {
            List<Estimate> ranked = recommend(md, h100, slo, specs);
            System.out.printf("%n== %s: %d feasible configs; top 4 by tok/s/GPU ==%n", slo.name(), ranked.size());
            for (Estimate e : ranked.subList(0, Math.min(4, ranked.size()))) {
                System.out.printf("  %-52s B=%4d  TPOT %5.1f ms  %7.0f tok/s/GPU  KV cap %,10d%n",
                        e.config(), e.batch(), e.tpotSeconds() * 1e3, e.tokPerSecPerGpu(), e.kvCapacity());
            }
            Estimate baseline = evaluate(md, h100, bf16, slo).orElse(null);
            System.out.printf("  baseline %-43s %s%n", bf16,
                    baseline == null ? "INFEASIBLE" : String.format("B=%4d  TPOT %5.1f ms  %7.0f tok/s/GPU",
                            baseline.batch(), baseline.tpotSeconds() * 1e3, baseline.tokPerSecPerGpu()));
            check(!ranked.isEmpty(), "some config meets " + slo.name());
            check(baseline == null || ranked.get(0).tokPerSecPerGpu() >= baseline.tokPerSecPerGpu(), "search >= baseline");
        }

        Slo interactive = slos.get(0), offline = slos.get(3);
        Config fp8 = new Config(8, WeightFormat.FP8_W8A8, KvFormat.FP8, Speculation.NONE);
        Config fp8Spec = new Config(8, WeightFormat.FP8_W8A8, KvFormat.FP8, specs.get(2));
        double gainInteractive = evaluate(md, h100, fp8Spec, interactive).orElseThrow().tokPerSecPerGpu()
                / evaluate(md, h100, fp8, interactive).orElseThrow().tokPerSecPerGpu();
        double gainOffline = evaluate(md, h100, fp8Spec, offline).orElseThrow().tokPerSecPerGpu()
                / evaluate(md, h100, fp8, offline).orElseThrow().tokPerSecPerGpu();
        System.out.printf("%nMTP-style speculation on FP8/TP=8: x%.2f tok/s/GPU at the interactive SLO, x%.2f offline%n",
                gainInteractive, gainOffline);
        check(gainInteractive > gainOffline, "speculation pays most where batches are SLO-capped");
        check(kvCapacity(md, h100, fp8) > 2 * kvCapacity(md, h100, bf16), "FP8 weights + FP8 KV more than double capacity");
        System.out.println("all DeploymentAdvisor self-checks passed");
    }
}
```

Output (verified, deterministic):

```text
cross-check vs Folder 01 RooflinePlanner: 23.4337 ms vs 23.4337 ms

== interactive TPOT<=20ms @4K: 62 feasible configs; top 4 by tok/s/GPU ==
  TP=2 W=FP8_W8A8 KV=FP8 spec=MTP/EAGLE g=1 a=.85      B= 113  TPOT  16.8 ms     3362 tok/s/GPU  KV cap    463,162
  TP=4 W=FP8_W8A8 KV=FP8 spec=MTP/EAGLE g=1 a=.85      B= 246  TPOT  20.0 ms     3082 tok/s/GPU  KV cap  1,356,942
  TP=2 W=FP8_W8A8 KV=FP8 spec=draft-1B g=3 a=.70       B= 103  TPOT  20.0 ms     2576 tok/s/GPU  KV cap    463,162
  TP=8 W=FP8_W8A8 KV=FP8 spec=MTP/EAGLE g=1 a=.85      B= 408  TPOT  20.0 ms     2553 tok/s/GPU  KV cap  3,144,502
  baseline TP=8 W=BF16 KV=BF16 spec=none               B= 165  TPOT  20.0 ms     1034 tok/s/GPU

== standard TPOT<=50ms @4K: 66 feasible configs; top 4 by tok/s/GPU ==
  TP=2 W=FP8_W8A8 KV=FP8 spec=MTP/EAGLE g=1 a=.85      B= 113  TPOT  16.8 ms     3362 tok/s/GPU  KV cap    463,162
  TP=4 W=FP8_W8A8 KV=FP8 spec=MTP/EAGLE g=1 a=.85      B= 331  TPOT  26.5 ms     3119 tok/s/GPU  KV cap  1,356,942
  TP=8 W=FP8_W8A8 KV=FP8 spec=MTP/EAGLE g=1 a=.85      B= 767  TPOT  36.8 ms     2608 tok/s/GPU  KV cap  3,144,502
  TP=2 W=FP8_W8A8 KV=FP8 spec=draft-1B g=3 a=.70       B= 113  TPOT  21.7 ms     2606 tok/s/GPU  KV cap    463,162
  baseline TP=8 W=BF16 KV=BF16 spec=none               B= 331  TPOT  35.0 ms     1182 tok/s/GPU

== long-context TPOT<=40ms @32K: 54 feasible configs; top 4 by tok/s/GPU ==
  TP=8 W=FP8_W8A8 KV=FP8 spec=MTP/EAGLE g=1 a=.85      B=  95  TPOT  16.8 ms      707 tok/s/GPU  KV cap  3,144,502
  TP=8 W=FP8_W8A8 KV=FP8 spec=draft-1B g=3 a=.70       B=  95  TPOT  17.6 ms      674 tok/s/GPU  KV cap  3,144,502
  TP=4 W=FP8_W8A8 KV=FP8 spec=draft-1B g=3 a=.70       B=  41  TPOT  15.5 ms      661 tok/s/GPU  KV cap  1,356,942
  TP=4 W=INT4_W4A16 KV=FP8 spec=MTP/EAGLE g=1 a=.85    B=  47  TPOT  17.9 ms      658 tok/s/GPU  KV cap  1,558,794
  baseline TP=8 W=BF16 KV=BF16 spec=none               B=  41  TPOT  27.7 ms      185 tok/s/GPU

== offline TPOT<=200ms @4K: 66 feasible configs; top 4 by tok/s/GPU ==
  TP=2 W=FP8_W8A8 KV=FP8 spec=MTP/EAGLE g=1 a=.85      B= 113  TPOT  16.8 ms     3362 tok/s/GPU  KV cap    463,162
  TP=4 W=FP8_W8A8 KV=FP8 spec=MTP/EAGLE g=1 a=.85      B= 331  TPOT  26.5 ms     3119 tok/s/GPU  KV cap  1,356,942
  TP=8 W=FP8_W8A8 KV=FP8 spec=MTP/EAGLE g=1 a=.85      B= 767  TPOT  36.8 ms     2608 tok/s/GPU  KV cap  3,144,502
  TP=2 W=FP8_W8A8 KV=FP8 spec=draft-1B g=3 a=.70       B= 113  TPOT  21.7 ms     2606 tok/s/GPU  KV cap    463,162
  baseline TP=8 W=BF16 KV=BF16 spec=none               B= 331  TPOT  35.0 ms     1182 tok/s/GPU

MTP-style speculation on FP8/TP=8: x1.27 tok/s/GPU at the interactive SLO, x1.23 offline
all DeploymentAdvisor self-checks passed
```

What the search says about Llama-3-70B on H100 (accepting the stated assumptions, including α = 0.85 for an
MTP/EAGLE-class drafter):

1. **FP8 weights + FP8 KV + a head-style drafter dominates every tier,** at **~3×** the BF16 baseline's tok/s/GPU at
   4K context and **~3.8×** at 32K (707 vs 185).
2. **KV capacity binds before the SLO for small TP.** The TP=2 FP8 winner runs B=113 at 16.8 ms TPOT for every SLO
   ≥ 20 ms, so loosening the SLO buys nothing there. Only larger TP (more KV) converts SLO slack into batch.
3. **Long context changes the winner to TP=8,** because 32K-token sequences need the KV capacity.
4. **Speculation pays most where the SLO caps the batch** (×1.27 interactive vs ×1.23 offline on FP8/TP=8). At
   unconstrained batch its value shrinks, consistent with §A.3.

These are model outputs, not measurements. The value of the tool is that every recommendation is traceable to
FLOPs, bytes, capacity, and an SLO, and it re-ranks instantly when a measured efficiency or acceptance rate replaces
an assumption.

---

## E. Production failure modes and P99 debugging

### F1 · Speculative decoding made peak throughput *worse*

- **Symptom:** speculation was enabled after latency wins in single-user tests. At peak traffic, tokens/s per GPU
  drops.
- **Signature:** large running batch, verify steps compute-bound, acceptance rate unchanged.
- **Root cause:** $B(\gamma+1)$ exceeds the GEMM knee, so verification costs 2.5× a step at B = 256 and a γ=4 draft
  gives 0.95× (§A.3).
- **Fix:** batch-adaptive γ (shrink or disable above a load threshold), cheaper drafters, separate latency and
  throughput tiers.

### F2 · Acceptance-rate collapse after a product change

- **Symptom:** latency regresses with no deploy to the serving stack.
- **Signature:** the acceptance-rate metric halves, correlated with a new use case (other languages, a new domain, a
  new structured-output schema).
- **Fix:** monitor acceptance per tenant and domain, retrain or fine-tune drafters on production traffic, and fall
  back to γ = 0 when acceptance drops below the break-even α.

### F3 · Outputs subtly less diverse after enabling speculation

- **Symptom:** evaluation shows a lower diversity or quality distribution at temperature > 0. Greedy outputs are
  identical.
- **Root cause:** greedy-match verification used under sampling (TV 0.34 in §A.1), or the drafter and target applied
  different sampling transforms (temperature, top-p, grammar masks).
- **Fix:** the rejection rule with *identical* logit processing on both sides. Add a distribution regression test
  (the §A.6 harness).

### F4 · INT4 model passes benchmarks, fails on long-context and math

- **Symptom:** average benchmark scores within ~1%, but regressions on multi-step reasoning, code, and long documents.
- **Root cause:** calibration data unlike production, quantization error accumulating over long generations, and
  salient channels not protected (RTN instead of AWQ/GPTQ).
- **Fix:** calibrate on production-like data, use AWQ/GPTQ group-128, evaluate on the tasks that matter (long-context
  QA, code, math), and keep a BF16 or FP8 tier for sensitive tenants.

### F5 · FP8 activations saturate on long or unusual inputs

- **Symptom:** quality drops on specific prompts; NaN-free but wrong.
- **Root cause:** static per-tensor activation scales calibrated on short, typical data. Rare inputs exceed 448 × scale
  and saturate.
- **Fix:** dynamic per-token (or per-tile) activation scales, recalibration with long and adversarial samples, and
  monitoring of saturation counts if the kernel exposes them.

### F6 · INT8 W8A8 accuracy cliff on one model family

- **Symptom:** a model quantizes fine at 7B and degrades badly at 70B.
- **Root cause:** emergent activation outlier channels plus per-tensor activation scales (0.097 error vs 0.019 with
  SmoothQuant in §B.3).
- **Fix:** SmoothQuant migration, per-token dynamic scales, or FP8.

### F7 · TP across nodes: decode ITL doubles

- **Symptom:** a model sharded TP=16 across two nodes "to get more memory" runs far slower than TP=8.
- **Root cause:** 160 latency-bound all-reduces per step over the inter-node network: 11 ms vs 2.4 ms at B=64. KV heads
  also replicate past $n_{kv}$ = 8.
- **Fix:** TP within the node, PP or replicas across nodes, FP8 to fit within a node.

### F8 · One slow GPU stalls the whole TP group

- **Symptom:** a replica's step time is erratic, and one GPU in the group runs hot or throttled.
- **Root cause:** TP is synchronous. Every all-reduce waits for the slowest rank (thermal throttling, ECC retirement,
  a noisy co-tenant on a shared PCIe switch, NVLink errors).
- **Signature:** per-rank kernel timelines show the others idling in NCCL waits.
- **Fix:** per-GPU health monitoring (clocks, power, ECC, NVLink error counters), automatic drain and replace, and
  NCCL timeouts with alerting instead of silent hangs.

### F9 · An FP8 deployment silently falls back to a slow path on older GPUs

- **Symptom:** the same FP8 checkpoint is 2× slower on A100 than expected.
- **Root cause:** A100 has no FP8 tensor cores, so kernels upcast (weight-only FP8 emulation) or fall back.
- **Fix:** a hardware-aware format choice (INT8 or W4A16 on Ampere, FP8 on Hopper, FP4 on Blackwell) and a startup
  assertion of the selected kernel path.

---

## F. FAANG L7 bar-raiser Q&A chains

### Q1 · "Prove speculative decoding doesn't change the output distribution."

- **L5 answer:** "The target model checks the draft's tokens, so the output is what the target would produce."
- **Why L5 fails:** "checks" is the naive argmax rule, which is biased under sampling (TV 0.34 in the toy experiment).
- **L7 principal defense:** with $\beta = \sum \min(p,q)$, the emission probability is
  $q\min(1,p/q) + (1-\beta)\cdot\max(0,p-q)/(1-\beta) = \min(p,q) + \max(0,p-q) = p$. Induct over positions; the bonus
  token comes from $p$. Empirically the TV is at the sampling noise floor (0.0167 vs 0.0176). Requirements: the
  identical logit processing on both sides, and the residual distribution on rejection.

### Q2 · "Turn on speculative decoding for our chat fleet?"

- **L5 answer:** "Yes, it gives 2–3× speedups."
- **Why L5 fails:** that is true at low batch and false at high batch. Verification goes compute-bound past
  $B(\gamma+1) \approx 300$ tokens (0.95× at B=256, γ=4).
- **L7 defense:**
  1. Segment by tier. Latency tiers run small batches, where speculation gives 1.8–2.6×. Throughput tiers run large
     batches, where it is neutral to negative.
  2. Pick a cheap drafter (EAGLE/MTP-class).
  3. Make γ adaptive to the running batch.
  4. Monitor acceptance per domain.
  5. Gate on goodput, not single-request latency.

### Q3 · "FP8 or INT4 for Llama-3-70B?"

- **L5 answer:** "INT4, it's smaller."
- **Why L5 fails:** it ignores the regime. INT4 W4A16 is memory-roof only. Past ~80 tokens per step it is
  compute-bound with dequantization overhead. And it is not more accurate.
- **L7 defense:**
  - **FP8 W8A8 on Hopper:** half the bytes, 2× compute roof, small accuracy loss with per-token activation scales. It
    is the default for throughput tiers (the advisor's winner).
  - **INT4 AWQ/GPTQ g128:** fits 70B on one GPU and wins low-batch latency and edge deployments. Validate on
    long-context and reasoning tasks.
  - **FP8 KV in both** for long context.
  - **INT8 per-channel weights** are actually more precise than FP8 weights. FP8's edge is range and tensor-core
    speed.

### Q4 · "Explain why 4-bit quantization works at all."

- **L5 answer:** "Neural networks are robust to noise."
- **Why L5 fails:** naive 4-bit RTN per channel gives 12.5% output error. It "works" only with structure.
- **L7 defense:**
  1. Group-wise scales (128 weights per scale/zero) bound each group's range.
  2. The error budget concentrates in a few salient channels, those that multiply large activations. AWQ scales them
     up with an equivalent transform folded into the previous op (−50% error, holding on held-out tokens). GPTQ
     compensates each column's error using second-order statistics.
  3. Outlier *activations* are handled by keeping activations in 16 bits (W4A16) or by rotations and smoothing (W4A8,
     W4A4 with Hadamard rotations).
  4. Calibration data must match the domain.

### Q5 · "Why two all-reduces per layer in Megatron TP, and what would you change for decode?"

- **L5 answer:** "One for attention and one for the MLP."
- **Why L5 fails:** it doesn't explain *why only two* (column → row pairing makes the middle local), and it misses
  that decode collectives are latency-bound.
- **L7 defense:**
  1. Column-parallel then row-parallel keeps elementwise ops local, leaving one reduction per block.
  2. At decode, messages are 16 KiB–4 MiB, below the ~2 MiB crossover, so per-call latency (~10 µs × 160 calls ≈
     1.6 ms per step) dominates.
  3. Changes: custom one-shot all-reduce kernels for small messages, fusing all-reduce with the next norm
     (reduce-scatter + norm + all-gather with sequence parallelism), overlapping communication with the next GEMM's
     independent work, and keeping TP within NVLink.
  4. Choose TP at the SLO (Folder 01: TP=8 beats TP=4 because of KV capacity).

### Q6 · "We need Llama-3-70B at TPOT ≤ 20 ms with the most tokens per dollar. Give me the config."

- **L5 answer:** "TP=8, BF16, vLLM defaults."
- **Why L5 fails:** that is the baseline the advisor beats by ~3×.
- **L7 defense:**
  1. Search the space: TP × {BF16, FP8, INT4} × KV {BF16, FP8} × speculation.
  2. Under the stated assumptions the search picks FP8 weights + FP8 KV + an MTP/EAGLE-class drafter. TP=2 wins
     tok/s/GPU at 4K (capacity-bound B=113 at 16.8 ms), TP=4 if you need larger batches or more context headroom,
     and TP=8 for 32K contexts.
  3. Then *measure*: replace the assumed MFU/MBU, acceptance rate and dequant penalty with benchmarks, and re-rank.
  4. Gate on quality evals for FP8.
  5. Re-run when traffic shifts to longer contexts.

### Q7 · "A TP=8 replica's p99 step time doubled; the other replicas are fine."

- **L5 answer:** "Restart it."
- **Why L5 fails:** it doesn't find the cause. The node may be bad, and a restart masks it until the next incident.
- **L7 defense:**
  1. TP is synchronous, so the group runs at the speed of its slowest GPU.
  2. Check per-GPU clocks, power, temperature, ECC and NVLink error counters, and the per-rank NCCL wait time in a
     timeline. The healthy ranks will show long all-reduce waits.
  3. Typical causes: thermal throttling, a degraded NVLink, PCIe contention, a failing HBM stack.
  4. Drain, replace, and file the hardware ticket.
  5. Add automated straggler detection (per-rank kernel time skew) and NCCL timeouts that page rather than hang.

---

## G. Invariants checklist

- [ ] Speculative sampling uses the min(1, p/q) rule + residual resampling with identical logit processing for draft
      and target. Greedy-match verification only at temperature 0.
- [ ] γ (and whether to speculate at all) adapts to the running batch. Acceptance rate is monitored per tenant and
      domain.
- [ ] Integer weight formats use per-channel or group scales. Activations use per-token or tile scales (or
      SmoothQuant). INT4 uses AWQ/GPTQ with domain-matched calibration.
- [ ] Quantization rollouts are gated on long-context, code, and reasoning evals, not averages.
- [ ] FP8 is chosen for Hopper/Blackwell. Ampere uses INT8 or W4A16. The selected kernel path is asserted at startup.
- [ ] TP stays within an NVLink domain and ≤ $n_{kv}$ (or the replication is accounted for). Cross-node scaling uses PP,
      EP or replicas.
- [ ] TP degree, formats and speculation are chosen by goodput at the SLO, with measured efficiencies replacing model
      assumptions.
- [ ] Per-GPU health (clocks, ECC, NVLink errors) and per-rank NCCL wait skew are monitored. NCCL timeouts alert
      rather than hang.

## H. References

1. Y. Leviathan, M. Kalman, Y. Matias. *Fast Inference from Transformers via Speculative Decoding.* ICML 2023.
2. C. Chen et al. *Accelerating Large Language Model Decoding with Speculative Sampling.* arXiv:2302.01318, 2023.
3. T. Cai et al. *Medusa: Simple LLM Inference Acceleration Framework with Multiple Decoding Heads.* ICML 2024.
4. Y. Li et al. *EAGLE* (ICML 2024), *EAGLE-2* (EMNLP 2024), *EAGLE-3* (arXiv:2503.01840, 2025).
5. F. Gloeckle et al. *Better & Faster Large Language Models via Multi-token Prediction.* ICML 2024.
6. DeepSeek-AI. *DeepSeek-V3 Technical Report.* arXiv:2412.19437, 2024 (MTP; fine-grained FP8).
7. P. Micikevicius et al. *FP8 Formats for Deep Learning.* arXiv:2209.05433, 2022.
8. T. Dettmers et al. *LLM.int8(): 8-bit Matrix Multiplication for Transformers at Scale.* NeurIPS 2022.
9. G. Xiao et al. *SmoothQuant: Accurate and Efficient Post-Training Quantization for Large Language Models.* ICML 2023.
10. E. Frantar et al. *GPTQ: Accurate Post-Training Quantization for Generative Pre-trained Transformers.* ICLR 2023.
11. J. Lin et al. *AWQ: Activation-aware Weight Quantization for LLM Compression and Acceleration.* MLSys 2024.
12. Open Compute Project. *OCP Microscaling Formats (MX) Specification v1.0*, 2023; NVIDIA Blackwell NVFP4
    documentation.
13. M. Shoeybi et al. *Megatron-LM: Training Multi-Billion Parameter Language Models Using Model Parallelism.*
    arXiv:1909.08053, 2019.
14. V. Korthikanti et al. *Reducing Activation Recomputation in Large Transformer Models.* MLSys 2023.
15. P. Patarasuk, X. Yuan. *Bandwidth Optimal All-reduce Algorithms for Clusters of Workstations.* JPDC 2009.
