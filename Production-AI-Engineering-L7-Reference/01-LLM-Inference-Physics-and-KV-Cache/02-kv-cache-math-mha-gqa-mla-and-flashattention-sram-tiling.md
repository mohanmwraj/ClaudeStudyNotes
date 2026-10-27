# 02 · KV Cache Math (MHA, GQA, MLA) and FlashAttention SRAM Tiling

> **Folder:** `01-LLM-Inference-Physics-and-KV-Cache/` · **File 2 of 3**
> **Anchoring papers:** Vaswani et al., *Attention Is All You Need* (2017) · Shazeer, *Fast Transformer Decoding: One
> Write-Head is All You Need* (2019, MQA) · Ainslie et al., *GQA* (EMNLP 2023) · DeepSeek-AI, *DeepSeek-V2* (2024, MLA)
> and *DeepSeek-V3 Technical Report* (2024) · Milakov & Gimelshein, *Online normalizer calculation for softmax* (2018)
> · Rabe & Staats, *Self-attention Does Not Need O(n²) Memory* (2021) · Dao et al., *FlashAttention* (NeurIPS 2022) ·
> Dao, *FlashAttention-2* (ICLR 2024) · Shah, Bikshandi, Zhang, Thakkar, Ramani & Dao, *FlashAttention-3* (NeurIPS 2024)
> · Dao, Haziza, Massa & Sizov, *Flash-Decoding for long-context inference* (2023) · Ye et al., *FlashInfer* (MLSys 2025)
> · Jiang et al., *Mistral 7B* (2023).
> **Code baseline:** Python 3.10+ (verified on CPython 3.14.5 + NumPy 2.5.4) · Java 21 (JDK 25.0.4, `--release 21`).
> **Previous:** [01 · Roofline](01-roofline-model-prefill-compute-bound-vs-decode-memory-bound.md) ·
> **Next:** [03 · PagedAttention and RadixAttention](03-pagedattention-block-tables-copy-on-write-and-radixattention.md)

---

## 0. The thesis in one paragraph

File 01 showed that the KV cache, not the weights, dominates decode bytes at long context, and that batching never
amortizes it. This file prices the KV cache to the byte and shows the two ways the industry fights it. The first is
**storing less per token**: MHA → GQA → MQA → MLA, plus sliding windows and FP8, a 71× range for the same model width.
The second is **moving it less often**: FlashAttention's SRAM tiling, which turns attention from an
$O(N^2)$-HBM-traffic, memory-bound kernel into a compute-bound one without changing the math. The two meet in one
quantity: decode attention intensity is $n_{\text{heads}}/n_{\text{kv}}$ FLOPs per byte. GQA-8 gives 8. MLA gives about
242, which is why DeepSeek's decode attention can approach the compute roof while Llama's never does.

---

## 1. What the KV cache is, and the exact formula

### 1.1 Why it exists

Autoregressive attention for token $t$ needs the keys and values of every earlier token $j \le t$. Without a cache,
generating token $t$ recomputes $K_{1..t}, V_{1..t}$ through every layer, so a length-$N$ generation costs $O(N^2)$
projection work. With a cache, each token's $K, V$ is computed **once**, at prefill or at the decode step that produced
it, and read every later step. That makes the cache a classic space-for-time trade. The space is the subject of this
file.

For one token, one layer stores:

```
K: [n_kv_heads, d_head]   (after RoPE has been applied - rotated keys are what get cached)
V: [n_kv_heads, d_head]
```

### 1.2 The formula, term by term

$$
\boxed{\;\text{KV bytes} = 2 \times n_{\text{layers}} \times n_{\text{kv\_heads}} \times d_{\text{head}} \times
\text{seq\_len} \times \text{batch} \times \text{bytes\_per\_elem}\;}
$$

| Factor | Meaning | Pitfall |
|--------|---------|---------|
| $2$ | one K and one V tensor | **MLA has no "2"**: one shared latent stands in for both (§2) |
| $n_{\text{layers}}$ | every layer has its own cache | hybrid models cache full length only in *global* layers (§2.7) |
| $n_{\text{kv\_heads}}$ | `num_key_value_heads` in `config.json` | **not** `num_attention_heads` unless the model is MHA |
| $d_{\text{head}}$ | per-head width | read `head_dim` if present. It need not equal `hidden_size / num_attention_heads` (e.g. Gemma-7B: 3072/16 = 192 but head_dim 256, ⚠ verify) |
| $\text{seq\_len}$ | tokens cached, prompt + generated | capped by `sliding_window` on windowed layers |
| $\text{bytes\_per\_elem}$ | 2 for BF16/FP16, 1 for FP8 | FP8 adds scales (per-tensor ≈ free; per-block ≈ 1–3%) |

When $d_k \ne d_v$ (DeepSeek's MHA counterfactual: 192 vs 128), replace $2 \times d_{\text{head}}$ by $d_k + d_v$.

### 1.3 MHA, MQA, GQA: one knob

```
MHA (n_kv = n_h)             GQA (1 < n_kv < n_h)            MQA (n_kv = 1)
 q0 q1 q2 q3 q4 q5 q6 q7      q0 q1 q2 q3 q4 q5 q6 q7         q0 q1 q2 q3 q4 q5 q6 q7
 |  |  |  |  |  |  |  |       \__|  \__|  \__|  \__|           \__\__\__\_|_/__/__/__/
 k0 k1 k2 k3 k4 k5 k6 k7       k0    k1    k2    k3                   k0
 v0 v1 v2 v3 v4 v5 v6 v7       v0    v1    v2    v3                   v0
 cache: 8 units/token         cache: 4 units/token (g=2)       cache: 1 unit/token
```

- **MQA** (Shazeer 2019) shares one K/V head across all query heads: an $n_h\times$ smaller cache, with measurable
  quality loss and training instability at scale.
- **GQA** (Ainslie et al. 2023) shares each K/V head across a *group* of $g = n_h/n_{kv}$ query heads. Existing MHA
  checkpoints can be **uptrained** to GQA by mean-pooling the heads of each group, then continuing pretraining for
  about 5% of the original compute. GQA-8 recovers nearly all of MHA's quality at a fraction of the cache. Llama 2 70B
  and every Llama 3 size use **8 KV heads**.
- The group size $g$ is also the decode attention intensity in FLOP/byte (BF16; File 01 §1.6). GQA makes the cache
  smaller *and* the attention kernel $g\times$ less memory-bound.

### 1.4 The exact byte table

From `kv_cache_math.py` (§4.1); every row is asserted in its self-test:

| Model | Kind | Elements / token / layer | **BF16 bytes / token** | FP8 bytes / token |
|-------|------|------------------------:|-----------------------:|------------------:|
| OPT-13B (vLLM paper's example) | MHA | 10,240 | **819,200** ("800 KB") | 409,600 |
| Llama-2-7B | MHA | 8,192 | 524,288 (512 KiB) | 262,144 |
| Falcon-7B | MQA | 128 | 8,192 | 4,096 |
| Mistral-7B-v0.1 | GQA-4 + SWA 4096 | 2,048 | 131,072 | 65,536 |
| Llama-3-8B | GQA-4 | 2,048 | 131,072 (128 KiB) | 65,536 |
| **Llama-3-70B** | GQA-8 | 2,048 | **327,680 (320 KiB)** | 163,840 |
| Llama-3.1-405B | GQA-16 | 2,048 | 516,096 (504 KiB) | 258,048 |
| **DeepSeek-V3** | MLA | **576** | **70,272 (68.6 KiB)** | 35,136 |

The vLLM paper's arithmetic checks out exactly: $2 \times 5120 \times 40 \times 2 = 819{,}200$ B per token, and 2,048
tokens is 1,677,721,600 B, "as much as 1.6 GB" per request.

### 1.5 Worked example: Llama-3-70B

$$
\kappa_{\text{L3-70B}} = 2 \times 80 \times 8 \times 128 \times 2 = 327{,}680\ \text{B} = 320\ \text{KiB per token}.
$$

| Scenario | KV cache |
|----------|---------:|
| 1 sequence × 8,192 tokens | **2.50 GiB** |
| 1 sequence × 32,768 | 10.00 GiB |
| 1 sequence × 131,072 (128K) | **40.00 GiB**, half an H100 for one user |
| 32 sequences × 8,192 | **80.00 GiB**, more than an entire H100 |
| Same model as MHA (64 KV heads), 1 × 128K | **320.00 GiB** (8× larger) |

**The silent integer-overflow trap.** Type the formula with 32-bit integers (Java `int`, C `int`, a Go `int32`) for
one 128K sequence:

$$
2 \cdot 80 \cdot 8 \cdot 128 \cdot 131072 \cdot 2 = 5 \cdot 2^{33} = 10 \cdot 2^{32} \;\equiv\; 0 \pmod{2^{32}}.
$$

The product wraps to **exactly zero**. A capacity planner built on it concludes that a 128K request costs nothing and
admits without limit. In Java the wrap happens at `* 131072`, where the running product $5\cdot 2^{32}$ is already
$\equiv 0$. The Java listing in §4.3 reproduces it and shows that `Math.multiplyExact` throws instead.

---

## 2. Multi-Head Latent Attention (MLA), from the equations to the bytes

### 2.1 The equations (DeepSeek-V2 §2.1; unchanged in V3)

Let $h_t \in \mathbb{R}^{d}$ be the hidden state, with $n_h = 128$ heads, $d_h = 128$, latent width $d_c = 512$,
query latent $d_c' = 1536$, and decoupled RoPE width $d_h^R = 64$.

**Low-rank joint KV compression.** Only $c_t^{KV}$ is cached:

$$
c_t^{KV} = W^{DKV} h_t \in \mathbb{R}^{d_c},\qquad
k_{t,i}^{C} = W_i^{UK} c_t^{KV},\qquad
v_{t,i}^{C} = W_i^{UV} c_t^{KV}\qquad(W_i^{UK}, W_i^{UV} \in \mathbb{R}^{d_h\times d_c}).
$$

**Low-rank query compression** saves activation memory during training and does not affect the cache:

$$
c_t^{Q} = W^{DQ} h_t \in \mathbb{R}^{d_c'},\qquad q_{t,i}^{C} = W_i^{UQ} c_t^{Q}.
$$

**Decoupled RoPE.** A small, head-*shared* rotated key is cached alongside the latent:

$$
q_{t,i}^{R} = \mathrm{RoPE}\big(W_i^{QR} c_t^{Q}\big) \in \mathbb{R}^{d_h^R},\qquad
k_t^{R} = \mathrm{RoPE}\big(W^{KR} h_t\big) \in \mathbb{R}^{d_h^R},
$$
$$
q_{t,i} = [q_{t,i}^{C}; q_{t,i}^{R}],\quad k_{j,i} = [k_{j,i}^{C}; k_j^{R}],\quad
o_{t,i} = \sum_{j\le t} \mathrm{softmax}_j\!\left(\frac{q_{t,i}^{\top} k_{j,i}}{\sqrt{d_h + d_h^R}}\right) v_{j,i}^{C},\quad
u_t = W^{O}[o_{t,1};\dots;o_{t,n_h}].
$$

**Cache per token per layer:** $d_c + d_h^R = 512 + 64 = 576$ elements. The DeepSeek-V2 paper writes this as
$\tfrac{9}{2} d_h$, "equivalent to GQA with only 2.25 groups", and that is exactly what the code prints.

### 2.2 Why RoPE has to be decoupled

The latent trick depends on **absorbing** $W^{UK}$ into the query side (§2.3). RoPE inserts a position-dependent
rotation $R_t$ between the projections:
$q^\top k = (R_t W^{UQ} c^Q)^\top (R_j W^{UK} c^{KV}) = c^{Q\top} W^{UQ\top} R_{t-j} W^{UK} c^{KV}$.
The middle matrix now depends on the relative position $t-j$, so it can't be pre-multiplied into a fixed weight. MLA
therefore keeps the content path ($k^C$, absorbable, no RoPE) separate from a tiny positional path ($k^R$, 64 dims,
shared by all heads, cached explicitly).

### 2.3 Weight absorption: MLA decode is MQA in latent space

For the content part of the score,

$$
q_{t,i}^{C\top} k_{j,i}^{C} = q_{t,i}^{C\top} W_i^{UK} c_j^{KV}
= \underbrace{\big(W_i^{UK\top} q_{t,i}^{C}\big)^{\top}}_{\tilde q_{t,i} \in \mathbb{R}^{d_c}} c_j^{KV},
$$

and for the output,

$$
u_t = \sum_i W_i^{O} W_i^{UV} \Big(\sum_j p_{t,j,i}\, c_j^{KV}\Big)
\;\Rightarrow\; W^{UV}\ \text{folds into}\ W^{O}.
$$

At decode time, then, each of the 128 query heads becomes a 576-wide query, $[\tilde q_{t,i}; q_{t,i}^R]$. All heads
attend to **the same** cached $[c_j^{KV}; k_j^R]$ keys and **the same** 512-wide values $c_j^{KV}$. It is multi-query
attention with $g = 128$ in a 576/512-dimensional space. FlashMLA (DeepSeek, open-sourced 2025) is a decode kernel for
exactly this shape over a paged cache with 64-token blocks.

### 2.4 The arithmetic intensity consequence

Per cached token, per layer, per decode step, with BF16 cache:

$$
F = n_h\big(\underbrace{2(d_c + d_h^R)}_{QK^\top} + \underbrace{2 d_c}_{PV}\big) = 128\,(1152 + 1024) = 278{,}528,
\qquad Q = 576 \times 2 = 1152\ \text{B},
\qquad I_{\text{MLA}} = 241.8\ \tfrac{\text{FLOP}}{\text{B}}.
$$

Compare GQA-8 (Llama-3-70B) at **8**, and the H100/H800 ridge at **295**. MLA decode attention sits right at the
ridge. Add one draft token per sequence (DeepSeek's multi-token prediction used for speculative decoding) and the
attention kernel becomes compute-bound. This is why FlashMLA advertises results in *both* regimes: up to ~3,000 GB/s
memory-bound and ~580 TFLOPS compute-bound on H800 at release (⚠ later versions report higher).

**Prefill does the opposite.** Absorption makes each score 1,088 FLOPs wide instead of 320 (= 192 + 128 with
decompressed K/V), so prefill pays 3.4× more attention FLOPs. Prefill is compute-bound already, so production MLA
implementations **decompress** K/V and run ordinary MHA (head dims 192/128) during prefill, and use the **absorbed** MQA
form during decode. That is two attention algorithms for one layer, chosen by roofline regime.

### 2.5 DeepSeek-V3 bytes, with counterfactuals

| Storage | Bytes / token (61 layers) | × 128K context |
|---------|--------------------------:|---------------:|
| **MLA latent, BF16** | **70,272** | **8.58 GiB** |
| MLA latent, FP8 (all 576 elements) | 35,136 | 4.29 GiB |
| MLA, FlashMLA FP8 format: 512 FP8 + 4 FP32 scales + 64 BF16 RoPE = 656 B/layer (⚠ verify, V3.2 kernels) | 40,016 | 4.88 GiB |
| GQA-8 counterfactual (192/128 head dims), BF16 | 312,320 | 38.12 GiB |
| **MHA counterfactual** (128 heads × (192+128)), BF16 | **4,997,120** | **610.00 GiB** |

MHA / MLA = **71.1×**. As plain MHA, one 128K-token DeepSeek-V3 conversation would need 610 GiB of KV, more than an
8×H100 node's entire HBM. The DeepSeek-V2 paper reports MLA cutting KV cache by 93.3% vs DeepSeek 67B and raising
maximum generation throughput 5.76×.

### 2.6 The MLA + tensor-parallelism trap

Tensor parallelism shards attention **by head**. GQA KV heads shard cleanly while $TP \le n_{kv}$. An MLA latent
belongs to **every** head, so it cannot be split:

| Model | TP | Bytes / token held per rank | Replication across the group |
|-------|---:|---------------------------:|-----------------------------:|
| Llama-3-70B | 1 | 327,680 | ×1 |
| Llama-3-70B | 4 | 81,920 | ×1 |
| Llama-3-70B | 8 | 40,960 | ×1 |
| Llama-3-70B | **16** | **40,960** | **×2** (TP > n_kv: each KV head duplicated) |
| DeepSeek-V3 | 1 | 70,272 | ×1 |
| DeepSeek-V3 | **8** | **70,272** | **×8** (every rank stores the full latent) |

At TP=8, MLA's 71× saving shrinks to an effective 71/8 ≈ 9× per GPU. The fix is **data-parallel attention** (SGLang
"DP attention"; DeepSeek's own deployment runs attention DP with experts EP). Each GPU owns whole sequences, and its
latent cache is not replicated. With roughly 37 GB of KV per H200 after FP8 weights (an approximation), TP-attention
holds 527K tokens for the group while DP-attention holds **4.21M**, the same hardware with 8× the context capacity. The
cost is that MLP/MoE layers now need an all-to-all or all-gather boundary between DP attention and EP experts
(Folder 02).

### 2.7 Sliding windows and hybrid local/global stacks

A layer with window $W$ caches at most $W$ tokens: $\text{bytes} \propto \min(L, W)$.

| Model | L = 4,096 | L = 32,768 | L = 131,072 |
|-------|----------:|-----------:|------------:|
| Mistral-7B-v0.1 (all 32 layers SWA, W = 4096) | 512 MiB | **512 MiB** (vs 4 GiB) | **512 MiB** (vs 16 GiB) |
| Synthetic Gemma-3-style 5:1 hybrid (40 local W = 1024, 8 global) | 288 MiB | 1.16 GiB (vs 6 GiB) | 4.16 GiB (vs 24 GiB) |

Two production consequences:

1. **The allocator must know which layers are windowed.** A paged allocator that sizes every layer at full length
   wastes 5–6× memory on hybrid models. vLLM grew a hybrid KV-cache manager with separate block pools per attention
   type for exactly this (⚠ verify the version you run).
2. **Prefix caching interacts with windows.** Blocks that slide out of every window are dead for decode, but a later
   request sharing the prefix still needs the *global* layers' blocks. Eviction must be per layer group.

Mistral-7B-v0.2 and later dropped the window. Always read the config of the exact checkpoint.

### 2.8 Quantizing the cache

- **FP8 KV (E4M3, per-tensor scale)** halves bytes and doubles the decode attention intensity (File 01). In vLLM it is
  `--kv-cache-dtype fp8` (E4M3/E5M2 variants). Quality risk concentrates in long-context retrieval tasks, so validate
  needle-in-a-haystack style evals before rollout.
- **Keys have outlier channels; values do not.** KIVI (Liu et al. 2024) and KVQuant (Hooper et al. 2024) quantize
  keys **per channel** and values **per token**, reaching 2–4 bits with small loss. Per-token key quantization is the
  naive error.
- Quantizing **before** RoPE vs **after** changes outlier structure. KVQuant quantizes pre-RoPE keys. Production
  kernels mostly cache post-RoPE keys, so they need per-channel scales or Hadamard-style rotations, the same
  "incoherent processing" idea FA3 uses for FP8 attention (§3.5).

---

## 3. FlashAttention: tiling attention into SRAM

### 3.1 Why standard attention is memory-bound

For one head with sequence length $N$ and head width $d$, standard attention runs three kernels:
$S = QK^\top/\sqrt d$ (written to HBM), $P = \mathrm{softmax}(S)$ (read $S$, write $P$), and $O = PV$ (read $P$).
HBM traffic is

$$
Q_{\text{std}} = \underbrace{4Nd}_{Q,K,V,O} + \underbrace{4N^2}_{S\ \text{write},\ S\ \text{read},\ P\ \text{write},\ P\ \text{read}}
\quad\text{elements},
$$

so it is quadratic in $N$ while the FLOPs ($4N^2 d$) only grow with $N^2$. Its intensity is about $d$ in FP16 (≈ 128),
below the ridge, and the softmax kernel in the middle has intensity ≈ 1. Priced for one Llama-3-70B layer (64 heads,
$N = 8192$, $d = 128$, BF16) by `flash_attention_ref.py`:

| Strategy | HBM bytes (one layer) | Time at 3.35 TB/s |
|----------|----------------------:|------------------:|
| Standard (materialize $S$, $P$) | **32.50 GiB** | **10.42 ms** |
| FlashAttention, K/V re-streamed per Q-tile, no L2 reuse ($B_r = 128$) | 16.25 GiB | 5.21 ms |
| FlashAttention, K/V re-reads served from L2 | **0.50 GiB** | **0.16 ms** |
| Compute: $4N^2 d \cdot n_h$ = 2.20 TFLOP at 989.4 TFLOP/s | — | **2.22 ms** |

Standard attention is memory-bound by 4.7×. FlashAttention is compute-bound by 14× *if* the K/V re-reads hit L2. Per
head, K plus V is $2 \times 8192 \times 128 \times 2$ B = 4 MiB, which fits easily in H100's 50 MiB L2, but only if the
CTAs for one head run *concurrently*. That is why FlashAttention's tile scheduler orders the grid head-major. At
$N = 131072$, the materialized $S$ for **one** head in FP32 is **64 GiB**, so standard attention cannot even run at long
context. FlashAttention's memory is $O(N)$.

The FlashAttention paper proves this formally. Standard attention needs $\Theta(Nd + N^2)$ HBM accesses, FlashAttention
needs $\Theta(N^2 d^2 / M)$ for SRAM size $M$, and no exact attention algorithm can do asymptotically better for all
$M \in [d, Nd]$.

### 3.2 The online softmax, derived

Softmax needs the row max (for numerical safety) and the row sum before any output can be normalized. That looks like
two full passes over $S$. The online formulation (Milakov & Gimelshein 2018) carries three running quantities per query
row, $m$ (max so far), $\ell$ (sum of exponentials relative to $m$) and $\mathbf{a}$ (un-normalized output), and
updates them block by block. For key/value block $j$ with scores $s_j$:

$$
m^{(j)} = \max\!\big(m^{(j-1)},\ \max s_j\big),\qquad
\alpha = e^{\,m^{(j-1)} - m^{(j)}},
$$
$$
\ell^{(j)} = \alpha\,\ell^{(j-1)} + \sum e^{\,s_j - m^{(j)}},\qquad
\mathbf{a}^{(j)} = \alpha\,\mathbf{a}^{(j-1)} + e^{\,s_j - m^{(j)}}\, V_j,
$$
$$
O = \mathbf{a}^{(T)} / \ell^{(T)},\qquad \mathrm{LSE} = m^{(T)} + \log \ell^{(T)}.
$$

**Invariant (proof by induction):** after block $j$, $m^{(j)} = \max_{k \le j} s_k$,
$\ell^{(j)} = \sum_{k\le j} e^{s_k - m^{(j)}}$ and $\mathbf{a}^{(j)} = \sum_{k \le j} e^{s_k - m^{(j)}} v_k$. Multiplying
the old state by $\alpha$ re-bases it from $m^{(j-1)}$ to $m^{(j)}$, and adding the new block's terms (already based at
$m^{(j)}$) preserves the invariant. At the end, $O$ is exactly $\mathrm{softmax}(s)\,V$: not an approximation, just a
reassociation. The NumPy reference matches naive attention to **~1e-15** in float64 across causal, GQA, ragged-tile,
chunked-prefill and decode shapes (§4.2 output).

**Why the max matters:** `flash_attention_ref.py` shows FP16 softmax of `[12, 11, -3]` without max-subtraction producing
`[nan, 0, 0]`, because $e^{12} = 162{,}755 > 65{,}504$ (the FP16 max) gives inf, and inf/inf is NaN. The online
algorithm keeps max-subtraction in a single pass.

### 3.3 FlashAttention-1 → FlashAttention-2: what changed and why it mattered

| | FlashAttention (2022) | FlashAttention-2 (2023) |
|-|----------------------|-------------------------|
| Loop order | outer over **K/V** blocks, inner over Q blocks. $O_i, \ell_i, m_i$ read and written to HBM every outer iteration | outer over **Q** blocks, inner over K/V. $O_i$ stays in registers for the whole pass |
| Normalization | rescales $O$ by $\mathrm{diag}(\ell)^{-1}$ every iteration | keeps $O$ un-normalized and divides **once** at the end. The backward pass stores only LSE |
| Parallelism | grid over (batch, head) | grid over (batch, head, **Q tile**), which fills 108–132 SMs even at small batch × heads |
| Warp partitioning | "split-K": warps split K/V, so partial results are combined through SMEM | warps split **Q**, each warp owns its rows, and no SMEM reduction is needed |
| Result (A100) | — | ~2× FA1. Forward reaches 50–73% of peak; ~225 TFLOP/s per A100 in end-to-end GPT training (72% MFU) |

The normalization change matters because of tensor-core economics. On A100, matmul FP16 is 312 TFLOP/s while non-matmul
FP32 is 19.5 TFLOP/s, so **one non-matmul FLOP costs as much as ~16 matmul FLOPs**. Every rescale removed from the inner
loop is worth a lot.

**Backward pass:** FA recomputes $S$ and $P$ from $Q, K$ and the stored LSE instead of reading a saved $N\times N$ $P$.
That is *more* FLOPs and *less* time, because the recompute runs at the compute roof while reading $P$ would run at the
memory roof.

### 3.4 Kernel execution flow: one CTA (Hopper / FA3-style)

```mermaid
sequenceDiagram
    autonumber
    participant HBM
    participant P as Producer warp (TMA)
    participant SMEM as SMEM ring (stages)
    participant C as Consumer warpgroups (WGMMA)
    participant REG as Registers (S, P, O fp32)
    P->>HBM: TMA load Q tile [Br x d]
    HBM-->>SMEM: Q tile (stays resident)
    loop for each KV tile j (stage = j mod S)
        P->>HBM: TMA load K_j, V_j  (async, signals mbarrier)
        HBM-->>SMEM: K_j, V_j into stage
        C->>SMEM: wait mbarrier(stage full)
        C->>REG: WGMMA  S = Q K_jᵀ        (tensor cores)
        C->>REG: m_new, α = exp(m-m_new), P = exp(S - m_new)   (MUFU exp2)
        C->>REG: WGMMA  O = α·O + P V_j   (tensor cores)
        C->>SMEM: release stage (mbarrier empty) so P can refill it
    end
    C->>REG: O = O / ℓ ; LSE = m + log ℓ
    C->>HBM: store O tile, LSE (TMA store)
```

The FA2 control flow is the same. The Hopper-specific parts are TMA (hardware bulk copies issued by one thread),
`mbarrier` transaction counts, warpgroup-wide asynchronous WGMMA, and the producer/consumer split.

### 3.5 FlashAttention-3: the softmax is the bottleneck now

On H100 SXM5, FP16 matmul is 989 TFLOP/s but the special-function units (exp) deliver only **3.9 TFLOP/s**. With
$d = 128$, each (query, key) pair costs 512 matmul FLOPs ($QK^\top$ + $PV$) and 1 exponential:

$$
\frac{t_{\exp}}{t_{\text{matmul}}} = \frac{1 / 3.9\times10^{12}}{512 / 989\times10^{12}} \approx 0.5 .
$$

Run serially, exp would take about half as long as all the tensor-core work. FA3's three techniques all hide that
latency or raise throughput:

1. **Producer–consumer warp specialization.** One warpgroup only issues TMA loads, and shrinks its register file with
   `setmaxnreg`. The others only compute, and grow theirs. Loads, GEMMs and softmax overlap across a circular SMEM
   buffer.
2. **Ping-pong scheduling between two consumer warpgroups.** Named barriers force WG1's softmax to run while WG2's
   GEMMs run, then swap. Within a warpgroup, the softmax of block $j$ also overlaps the $QK^\top$ GEMM of block $j+1$
   (a two-stage pipeline).
3. **FP8 with block quantization and incoherent processing.** A random orthogonal (Hadamard) transform applied to Q
   and K spreads outliers before FP8 quantization. The paper reports **2.6× lower numerical error** than baseline FP8
   attention. FP8 WGMMA needs a k-major V operand, so V is transposed in-kernel.

Reported results: **1.5–2.0× FA2**, up to **740 TFLOP/s FP16 (75% of peak)** and close to **1.2 PFLOP/s FP8** on H100.

Blackwell kernels (FlashAttention-4 and cuDNN) push further on the same axis. They emulate part of `exp2` with
polynomial FMA arithmetic and rescale the running output only when the max grows by enough to matter (⚠ verify against
the FA4 release you use).

### 3.6 SRAM and register budget per CTA

A CTA's tiles must fit 227 KiB of SMEM on H100. The fp32 $S$ and $O$ accumulators live in registers: 255 per thread
max, 64K per SM. Illustrative configurations, computed by the listing (FA3 picks tiles per head dim and mask type; ⚠
see its tile-size heuristics):

| $B_r$ | $B_c$ | $d$ | K/V stages | SMEM (Q + stages × (K+V)) | Fits? | fp32 accumulator regs/thread (64 rows per warpgroup) |
|------:|------:|----:|-----------:|--------------------------:|:-----:|----------------------------------------------------:|
| 128 | 128 | 128 | 2 | 160.0 KiB | ✓ | 128 |
| 128 | 176 | 128 | 2 | 208.0 KiB | ✓ | 152 |
| 128 | 128 | 128 | 3 | 224.0 KiB | ✓ (tight) | 128 |
| 128 | 80 | 256 | 2 | 224.0 KiB | ✓ (tight) | 168 |
| 64 | 64 | 64 | 2 | 40.0 KiB | ✓ (2+ CTAs/SM) | 64 |

The trade-off: larger $B_c$ amortizes softmax bookkeeping and pipeline overhead but needs more registers and SMEM.
More stages hide TMA latency but cost SMEM. $d = 256$ halves the affordable $B_c$. That is why head dim 256 kernels are
slower per FLOP, and why model designers favor $d_h = 128$.

### 3.7 Decode is a different kernel: Flash-Decoding, split-KV, cascade

FlashAttention parallelizes over (batch × heads × Q tiles). In decode $L_q = 1$, so there is one Q tile, and a batch of
8 sequences × 8 KV heads launches only 64 CTAs on a 132-SM GPU. More than half the machine idles while each CTA walks a
128K-token context serially.

**Flash-Decoding** (2023) splits the KV sequence into $s$ chunks. Each chunk becomes an independent CTA that returns a
partial $(O_s, \mathrm{LSE}_s)$, and a tiny second kernel merges them:

$$
\mathrm{LSE} = \log \sum_s e^{\mathrm{LSE}_s},\qquad O = \sum_s e^{\mathrm{LSE}_s - \mathrm{LSE}}\, O_s .
$$

The merge is **associative and commutative**. It is the same algebra as the online softmax, applied to *states* instead
of blocks, and it shows up across serving:

- **Split-KV decode** (FlashDecoding, FlashInfer, vLLM's paged-attention V2 partitions): fills the GPU at long context.
  The authors report up to 8× faster decoding for very long sequences.
- **Cascade / shared-prefix attention** (FlashInfer cascade, Hydragen): attend once to a prefix shared by many requests,
  which is a *batched* GEMM with high intensity, then separately to each private suffix, then merge. The reference
  shows 8 requests sharing a 1,024-token prefix with exact results, reading the prefix KV **once instead of 8 times**.
- **Ring attention / context parallelism:** each device holds a KV shard, partial states circulate, and devices merge.

All verified to ~1e-16 in §4.2.

---

## 4. Production code blueprints

### 4.1 Python: exact KV sizing from `config.json` (the hardened replacement for the whiteboard formula)

```python
"""kv_cache_math.py - exact KV-cache byte sizing for MHA / GQA / MQA / MLA / sliding-window (stdlib only).

Every KV number in 02-kv-cache-math-mha-gqa-mla-and-flashattention-sram-tiling.md is printed here.
Geometries are transcribed from each model's Hugging Face config.json (fields named in comments).
"""
from __future__ import annotations

from dataclasses import dataclass

KiB, MiB, GiB = 2**10, 2**20, 2**30


@dataclass(frozen=True)
class KvGeometry:
    name: str
    n_layers: int                    # num_hidden_layers
    n_heads: int                     # num_attention_heads (query heads)
    n_kv_heads: int                  # num_key_value_heads; ignored for MLA
    head_dim: int                    # K head dim (hidden_size / num_attention_heads unless head_dim given)
    v_head_dim: int | None = None    # defaults to head_dim
    kv_lora_rank: int = 0            # MLA: width d_c of the compressed latent c_KV
    qk_rope_head_dim: int = 0        # MLA: width d_h^R of the decoupled, head-shared RoPE key
    qk_nope_head_dim: int = 0        # MLA: per-head non-RoPE q/k width (needed only for the MHA counterfactual)
    sliding_window: int | None = None
    sliding_layers: int = 0          # how many layers use the window; the rest attend globally

    @property
    def kind(self) -> str:
        if self.kv_lora_rank:
            return "MLA"
        if self.n_kv_heads == self.n_heads:
            return "MHA"
        if self.n_kv_heads == 1:
            return "MQA"
        return f"GQA (g={self.n_heads // self.n_kv_heads})"

    def elems_per_token_per_layer(self) -> int:
        if self.kv_lora_rank:
            # One latent c_KV (d_c) + one RoPE key k^R (d_h^R), both SHARED by every head.
            # There is no separate "V" tensor: V is re-derived from c_KV (or absorbed into W_O).
            return self.kv_lora_rank + self.qk_rope_head_dim
        return self.n_kv_heads * (self.head_dim + (self.v_head_dim or self.head_dim))

    def bytes_per_token(self, bytes_per_elem: float = 2.0) -> float:
        """Per-token KV across all layers at full length (no window cap)."""
        return self.n_layers * self.elems_per_token_per_layer() * bytes_per_elem

    def kv_bytes(self, seq_len: int, batch: int = 1, bytes_per_elem: float = 2.0) -> float:
        """Exact cache bytes for `batch` sequences of `seq_len` tokens (window-capped layers honored)."""
        per_layer_tok = self.elems_per_token_per_layer() * bytes_per_elem
        windowed = min(seq_len, self.sliding_window) if self.sliding_window else seq_len
        global_layers = self.n_layers - self.sliding_layers
        return batch * per_layer_tok * (global_layers * seq_len + self.sliding_layers * windowed)

    def mha_counterfactual(self) -> "KvGeometry":
        """The same model with full multi-head K/V (one K and one V per query head)."""
        if self.kv_lora_rank:
            return KvGeometry(self.name + " as MHA", self.n_layers, self.n_heads, self.n_heads,
                              self.qk_nope_head_dim + self.qk_rope_head_dim, self.v_head_dim)
        return KvGeometry(self.name + " as MHA", self.n_layers, self.n_heads, self.n_heads,
                          self.head_dim, self.v_head_dim)


def from_hf_config(name: str, c: dict) -> KvGeometry:
    n_heads = c["num_attention_heads"]
    head_dim = c.get("head_dim") or c["hidden_size"] // n_heads
    sliding = c.get("sliding_window")
    return KvGeometry(
        name=name,
        n_layers=c["num_hidden_layers"],
        n_heads=n_heads,
        n_kv_heads=c.get("num_key_value_heads", n_heads),
        head_dim=head_dim,
        v_head_dim=c.get("v_head_dim"),
        kv_lora_rank=c.get("kv_lora_rank", 0),
        qk_rope_head_dim=c.get("qk_rope_head_dim", 0),
        qk_nope_head_dim=c.get("qk_nope_head_dim", 0),
        sliding_window=sliding,
        sliding_layers=c.get("sliding_layers", c["num_hidden_layers"] if sliding else 0),
    )


HF_CONFIGS: dict[str, dict] = {
    # vLLM paper's running example (Kwon et al. §3): "800 KB per token"
    "OPT-13B": {"num_hidden_layers": 40, "num_attention_heads": 40, "hidden_size": 5120},
    "Llama-2-7B": {"num_hidden_layers": 32, "num_attention_heads": 32, "num_key_value_heads": 32,
                   "hidden_size": 4096},
    # Falcon-7B: multi_query=true, n_head=71, hidden 4544 -> head_dim 64 (normalized field names)
    "Falcon-7B": {"num_hidden_layers": 32, "num_attention_heads": 71, "num_key_value_heads": 1,
                  "hidden_size": 4544},
    # Mistral-7B-v0.1: SWA on every layer (v0.2+ dropped the window)
    "Mistral-7B-v0.1": {"num_hidden_layers": 32, "num_attention_heads": 32, "num_key_value_heads": 8,
                        "hidden_size": 4096, "sliding_window": 4096},
    "Llama-3-8B": {"num_hidden_layers": 32, "num_attention_heads": 32, "num_key_value_heads": 8,
                   "hidden_size": 4096},
    "Llama-3-70B": {"num_hidden_layers": 80, "num_attention_heads": 64, "num_key_value_heads": 8,
                    "hidden_size": 8192},
    "Llama-3.1-405B": {"num_hidden_layers": 126, "num_attention_heads": 128, "num_key_value_heads": 8,
                       "hidden_size": 16384},
    # DeepSeek-V3 / R1: MLA (q_lora_rank 1536 does not affect the cache)
    "DeepSeek-V3": {"num_hidden_layers": 61, "num_attention_heads": 128, "num_key_value_heads": 128,
                    "hidden_size": 7168, "kv_lora_rank": 512, "qk_rope_head_dim": 64,
                    "qk_nope_head_dim": 128, "v_head_dim": 128},
    # Synthetic Gemma-3-style hybrid: 5 local (window 1024) : 1 global, 48 layers, GQA-2
    "Hybrid-5:1 (synthetic)": {"num_hidden_layers": 48, "num_attention_heads": 16, "num_key_value_heads": 8,
                               "hidden_size": 2048, "sliding_window": 1024, "sliding_layers": 40},
}
MODELS = {n: from_hf_config(n, c) for n, c in HF_CONFIGS.items()}

FLASHMLA_FP8_BYTES_PER_TOKEN_LAYER = 512 + 4 * 4 + 64 * 2   # fp8 latent + 4 fp32 scales + bf16 RoPE key


def per_rank_bytes_per_token(g: KvGeometry, tp: int, bytes_per_elem: float = 2.0) -> tuple[float, float]:
    """(bytes per token held by EACH tensor-parallel rank, replication factor across the TP group)."""
    total = g.bytes_per_token(bytes_per_elem)
    if g.kv_lora_rank:
        return total, float(tp)                     # latent is head-shared: every TP rank keeps all of it
    kv_per_rank = max(1, g.n_kv_heads // tp)        # tp > n_kv -> each KV head is replicated
    per_rank = g.n_layers * kv_per_rank * (g.head_dim + (g.v_head_dim or g.head_dim)) * bytes_per_elem
    return per_rank, per_rank * tp / total


def fmt(nbytes: float) -> str:
    for unit, div in (("GiB", GiB), ("MiB", MiB), ("KiB", KiB)):
        if nbytes >= div:
            return f"{nbytes / div:,.2f} {unit}"
    return f"{nbytes:,.0f} B"


def main() -> None:
    print("== Per-token KV cache, all layers ==")
    print(f"{'model':24s} {'kind':12s} {'elems/tok/layer':>15s} {'BF16 B/token':>13s} {'FP8 B/token':>12s}")
    for g in MODELS.values():
        print(f"{g.name:24s} {g.kind:12s} {g.elems_per_token_per_layer():15,d} "
              f"{g.bytes_per_token(2):13,.0f} {g.bytes_per_token(1):12,.0f}")

    opt = MODELS["OPT-13B"]
    assert opt.bytes_per_token() == 819_200                                  # "800 KB"
    assert opt.kv_bytes(2048) == 1_677_721_600                              # "as much as 1.6 GB"

    l70 = MODELS["Llama-3-70B"]
    assert l70.bytes_per_token() == 327_680 == 320 * KiB
    print(f"\n== {l70.name} ({l70.kind}) ==")
    for L in (8192, 32768, 131072):
        print(f"  1 seq x {L:>6}: {fmt(l70.kv_bytes(L))}")
    print(f"  32 seq x 8192: {fmt(l70.kv_bytes(8192, 32))}")
    mha = l70.mha_counterfactual()
    print(f"  as MHA (64 KV heads): {mha.bytes_per_token():,.0f} B/token = "
          f"{mha.bytes_per_token() / l70.bytes_per_token():.0f}x; 1 x 131072 = {fmt(mha.kv_bytes(131072))}")
    assert l70.kv_bytes(131072) == 40 * GiB

    naive_int32 = (2 * 80 * 8 * 128 * 131072 * 1 * 2) & 0xFFFFFFFF          # what Java `int` math returns
    print(f"  int32 wraparound of 2*80*8*128*131072*1*2 = {naive_int32} (exact value is 5 * 2^33)")
    assert naive_int32 == 0

    ds = MODELS["DeepSeek-V3"]
    ds_mha = ds.mha_counterfactual()
    ds_gqa8 = KvGeometry("DeepSeek-V3 as GQA-8", 61, 128, 8, 192, 128)
    print(f"\n== {ds.name} (MLA: d_c={ds.kv_lora_rank}, d_h^R={ds.qk_rope_head_dim}) ==")
    rows = [
        ("MLA latent, BF16", ds.bytes_per_token(2)),
        ("MLA latent, FP8 (all 576 elems)", ds.bytes_per_token(1)),
        ("MLA, FlashMLA FP8 (656 B/layer)", FLASHMLA_FP8_BYTES_PER_TOKEN_LAYER * ds.n_layers),
        ("GQA-8 counterfactual, BF16", ds_gqa8.bytes_per_token(2)),
        ("MHA counterfactual, BF16", ds_mha.bytes_per_token(2)),
    ]
    for label, b in rows:
        print(f"  {label:34s} {b:>12,.0f} B/token   x 131072 = {fmt(b * 131072):>12s}")
    assert ds.bytes_per_token() == 70_272 and ds_mha.bytes_per_token() == 4_997_120
    print(f"  MHA / MLA = {ds_mha.bytes_per_token() / ds.bytes_per_token():.1f}x; "
          f"MLA = GQA with {ds.elems_per_token_per_layer() / (2 * 128):.2f} KV heads of dim 128")

    print("\n== Tensor-parallel sharding of the cache ==")
    for g, tps in ((l70, (1, 4, 8, 16)), (ds, (1, 8))):
        for tp in tps:
            per_rank, rep = per_rank_bytes_per_token(g, tp)
            print(f"  {g.name:12s} TP={tp:2d}: {per_rank:>9,.0f} B/token/rank, replication x{rep:.0f}")
    assert per_rank_bytes_per_token(l70, 16) == (40_960, 2.0)
    assert per_rank_bytes_per_token(ds, 8) == (70_272, 8.0)

    free_per_gpu = 37e9   # ~141 GB H200 x 0.9 minus ~86 GB FP8 weights/GPU minus activations (approx.)
    tp_tokens = free_per_gpu / ds.bytes_per_token()
    print(f"  DeepSeek-V3 on 8xH200, ~37 GB KV/GPU: TP-attention holds {tp_tokens / 1e3:,.0f}K tokens total; "
          f"DP-attention holds {8 * tp_tokens / 1e6:,.2f}M")

    mis = MODELS["Mistral-7B-v0.1"]
    hyb = MODELS["Hybrid-5:1 (synthetic)"]
    print("\n== Sliding-window caps ==")
    for g in (mis, hyb):
        for L in (4096, 32768, 131072):
            full = g.bytes_per_token() * L
            print(f"  {g.name:24s} L={L:>6}: {fmt(g.kv_bytes(L)):>11s}  (no window: {fmt(full)})")
    assert mis.kv_bytes(131072) == mis.kv_bytes(4096) == 512 * MiB
    print("\nall KV-cache self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified, deterministic):

```text
== Per-token KV cache, all layers ==
model                    kind         elems/tok/layer  BF16 B/token  FP8 B/token
OPT-13B                  MHA                   10,240       819,200      409,600
Llama-2-7B               MHA                    8,192       524,288      262,144
Falcon-7B                MQA                      128         8,192        4,096
Mistral-7B-v0.1          GQA (g=4)              2,048       131,072       65,536
Llama-3-8B               GQA (g=4)              2,048       131,072       65,536
Llama-3-70B              GQA (g=8)              2,048       327,680      163,840
Llama-3.1-405B           GQA (g=16)             2,048       516,096      258,048
DeepSeek-V3              MLA                      576        70,272       35,136
Hybrid-5:1 (synthetic)   GQA (g=2)              2,048       196,608       98,304

== Llama-3-70B (GQA (g=8)) ==
  1 seq x   8192: 2.50 GiB
  1 seq x  32768: 10.00 GiB
  1 seq x 131072: 40.00 GiB
  32 seq x 8192: 80.00 GiB
  as MHA (64 KV heads): 2,621,440 B/token = 8x; 1 x 131072 = 320.00 GiB
  int32 wraparound of 2*80*8*128*131072*1*2 = 0 (exact value is 5 * 2^33)

== DeepSeek-V3 (MLA: d_c=512, d_h^R=64) ==
  MLA latent, BF16                         70,272 B/token   x 131072 =     8.58 GiB
  MLA latent, FP8 (all 576 elems)          35,136 B/token   x 131072 =     4.29 GiB
  MLA, FlashMLA FP8 (656 B/layer)          40,016 B/token   x 131072 =     4.88 GiB
  GQA-8 counterfactual, BF16              312,320 B/token   x 131072 =    38.12 GiB
  MHA counterfactual, BF16              4,997,120 B/token   x 131072 =   610.00 GiB
  MHA / MLA = 71.1x; MLA = GQA with 2.25 KV heads of dim 128

== Tensor-parallel sharding of the cache ==
  Llama-3-70B  TP= 1:   327,680 B/token/rank, replication x1
  Llama-3-70B  TP= 4:    81,920 B/token/rank, replication x1
  Llama-3-70B  TP= 8:    40,960 B/token/rank, replication x1
  Llama-3-70B  TP=16:    40,960 B/token/rank, replication x2
  DeepSeek-V3  TP= 1:    70,272 B/token/rank, replication x1
  DeepSeek-V3  TP= 8:    70,272 B/token/rank, replication x8
  DeepSeek-V3 on 8xH200, ~37 GB KV/GPU: TP-attention holds 527K tokens total; DP-attention holds 4.21M

== Sliding-window caps ==
  Mistral-7B-v0.1          L=  4096:  512.00 MiB  (no window: 512.00 MiB)
  Mistral-7B-v0.1          L= 32768:  512.00 MiB  (no window: 4.00 GiB)
  Mistral-7B-v0.1          L=131072:  512.00 MiB  (no window: 16.00 GiB)
  Hybrid-5:1 (synthetic)   L=  4096:  288.00 MiB  (no window: 768.00 MiB)
  Hybrid-5:1 (synthetic)   L= 32768:    1.16 GiB  (no window: 6.00 GiB)
  Hybrid-5:1 (synthetic)   L=131072:    4.16 GiB  (no window: 24.00 GiB)

all KV-cache self-checks passed
```

### 4.2 Python: FlashAttention-2, Flash-Decoding, cascade, and the IO/SRAM math in NumPy

The loops mirror the CUDA grid. `(head, q_tile)` is a CTA, and the `j` loop is the SMEM pipeline. The naive
implementation (`naive_attention`) is the bottleneck pattern: it materializes $S$ and $P$, which is $O(N^2)$ memory.

```python
"""flash_attention_ref.py - NumPy reference for FlashAttention-2 forward (tiled online softmax),
Flash-Decoding (split-KV + log-sum-exp merge), cascade/shared-prefix attention, and the HBM/SRAM math.

The loops mirror the CUDA grid: (head, q-tile) is one thread block (CTA); the inner j-loop is the
KV pipeline a CTA streams through SRAM. Validated against naive attention to ~1e-15 in float64.
"""
from __future__ import annotations

import math

import numpy as np


def naive_attention(q: np.ndarray, k: np.ndarray, v: np.ndarray, causal: bool = False):
    """q: [Hq, Lq, d]; k: [Hkv, Lk, d]; v: [Hkv, Lk, dv]. Materializes S and P: O(Lq*Lk) memory."""
    hq, lq, d = q.shape
    hkv, lk, _ = k.shape
    g = hq // hkv
    kk, vv = np.repeat(k, g, axis=0), np.repeat(v, g, axis=0)
    s = q @ kk.transpose(0, 2, 1) / math.sqrt(d)
    if causal:  # bottom-right aligned: query row i sits at absolute position (Lk - Lq) + i
        mask = np.arange(lk)[None, :] > ((lk - lq) + np.arange(lq))[:, None]
        s = np.where(mask[None], -np.inf, s)
    m = s.max(-1, keepdims=True)
    p = np.exp(s - m)
    l = p.sum(-1, keepdims=True)
    return (p / l) @ vv, (m + np.log(l))[..., 0]


def flash_attention_fwd(q: np.ndarray, k: np.ndarray, v: np.ndarray, causal: bool = False,
                        br: int = 64, bc: int = 64):
    """FlashAttention-2 forward. Returns (O, LSE); LSE = m + log(l) is all the backward pass keeps."""
    hq, lq, d = q.shape
    hkv, lk, dv = v.shape
    g, off, scale = hq // hkv, lk - lq, 1.0 / math.sqrt(d)
    o = np.empty((hq, lq, dv), dtype=q.dtype)
    lse = np.empty((hq, lq), dtype=q.dtype)
    for h in range(hq):                                   # grid.y: one CTA per (head, q-tile)
        kh, vh = k[h // g], v[h // g]                     # GQA: index the shared KV head, never copy
        for i0 in range(0, lq, br):                       # grid.x  (FA2: parallel over sequence)
            qi = q[h, i0:i0 + br] * scale                 # Q tile loaded to SRAM once, pre-scaled
            rows = qi.shape[0]
            m = np.full(rows, -np.inf)                    # running row max      (registers)
            l = np.zeros(rows)                            # running row sum      (registers)
            acc = np.zeros((rows, dv))                    # UN-normalized output (registers, fp32)
            j_end = min(lk, off + i0 + rows) if causal else lk   # skip tiles entirely above the diagonal
            for j0 in range(0, j_end, bc):                # stream K_j, V_j tiles HBM -> SRAM
                kj, vj = kh[j0:j0 + bc], vh[j0:j0 + bc]
                s = qi @ kj.T                             # GEMM-I  (tensor cores), Br x Bc in registers
                if causal and j0 + kj.shape[0] - 1 > off + i0:   # only diagonal tiles pay for masking
                    qpos = off + i0 + np.arange(rows)[:, None]
                    kpos = j0 + np.arange(kj.shape[0])[None, :]
                    s = np.where(kpos > qpos, -np.inf, s)
                m_new = np.maximum(m, s.max(axis=1))
                p = np.exp(s - m_new[:, None])            # P~ = exp(S - m_new)   (SFU/MUFU exp2)
                alpha = np.exp(m - m_new)                 # rescale factor for the old state
                l = alpha * l + p.sum(axis=1)
                acc = alpha[:, None] * acc + p @ vj       # GEMM-II (tensor cores)
                m = m_new
            o[h, i0:i0 + rows] = acc / l[:, None]         # FA2: a single normalization at the end
            lse[h, i0:i0 + rows] = m + np.log(l)
    return o, lse


def merge_states(states):
    """Merge (O_s, LSE_s) computed over DISJOINT key sets into attention over their union.
    Associative and commutative: the primitive behind Flash-Decoding, cascade attention, ring attention."""
    os_ = np.stack([s[0] for s in states])
    lses = np.stack([s[1] for s in states])
    lse = np.logaddexp.reduce(lses, axis=0)
    w = np.exp(lses - lse[None])
    return (w[..., None] * os_).sum(axis=0), lse


def flash_decoding(q: np.ndarray, k: np.ndarray, v: np.ndarray, n_splits: int):
    """Decode-time split-KV: each split is an independent CTA; a tiny second kernel merges them."""
    bounds = np.linspace(0, k.shape[1], n_splits + 1).astype(int)
    parts = [flash_attention_fwd(q, k[:, a:b], v[:, a:b]) for a, b in zip(bounds[:-1], bounds[1:]) if b > a]
    return merge_states(parts)


# --------------------------------------------------------------------------- IO and SRAM accounting
def hbm_bytes(n: int, d: int, heads: int, br: int, bytes_per: int = 2) -> dict[str, float]:
    """Forward-pass HBM traffic for self-attention over n tokens (non-causal), all heads."""
    naive = 4 * n * d + 4 * n * n           # read Q,K | write S | read S, write P | read P,V | write O
    tr = math.ceil(n / br)
    flash_no_l2 = 2 * n * d + 2 * n * d * tr  # Q in, O out, K and V re-streamed once per Q tile
    flash_l2 = 4 * n * d                      # K/V re-reads served by L2 (head-major CTA order)
    return {k_: heads * bytes_per * v_ for k_, v_ in
            (("naive", naive), ("flash, no L2 reuse", flash_no_l2), ("flash, ideal L2", flash_l2))}


def smem_bytes(br: int, bc: int, d: int, stages: int, bytes_per: int = 2) -> int:
    """Shared memory for one CTA: a Q tile plus `stages` double/triple-buffered (K, V) tiles."""
    return br * d * bytes_per + 2 * bc * d * bytes_per * stages


def accum_regs_per_thread(rows_per_wg: int, bc: int, dv: int, threads_per_wg: int = 128) -> float:
    """32-bit registers per thread for the fp32 S tile + fp32 O accumulator of one warpgroup."""
    return (rows_per_wg * bc + rows_per_wg * dv) / threads_per_wg


# --------------------------------------------------------------------------- self-test / report
def main() -> None:
    rng = np.random.default_rng(7)
    cases = [  # (Hq, Hkv, Lq, Lk, d, causal, br, bc) - prefill, chunked prefill, decode, ragged tiles
        (8, 8, 256, 256, 64, True, 64, 64),
        (8, 2, 200, 200, 64, True, 64, 48),
        (8, 2, 96, 480, 64, True, 32, 64),
        (16, 2, 1, 1000, 128, False, 64, 128),
        (4, 1, 130, 130, 32, False, 64, 64),
    ]
    worst = 0.0
    for hq, hkv, lq, lk, d, causal, br, bc in cases:
        q = rng.standard_normal((hq, lq, d))
        k = rng.standard_normal((hkv, lk, d))
        v = rng.standard_normal((hkv, lk, d))
        o_ref, lse_ref = naive_attention(q, k, v, causal)
        o, lse = flash_attention_fwd(q, k, v, causal, br, bc)
        err = max(np.abs(o - o_ref).max(), np.abs(lse - lse_ref).max())
        worst = max(worst, err)
        print(f"FA2 Hq={hq:2d} Hkv={hkv} Lq={lq:4d} Lk={lk:4d} d={d:3d} causal={causal!s:5s} "
              f"Br={br} Bc={bc}: max|err|={err:.2e}")
    assert worst < 1e-12

    q = rng.standard_normal((32, 1, 128))
    k = rng.standard_normal((8, 4096, 128))
    v = rng.standard_normal((8, 4096, 128))
    o_ref, lse_ref = naive_attention(q, k, v)
    for splits in (1, 4, 16, 64):
        o, lse = flash_decoding(q, k, v, splits)
        print(f"Flash-Decoding splits={splits:2d}: max|err|={np.abs(o - o_ref).max():.2e}")
        assert np.abs(o - o_ref).max() < 1e-12 and np.abs(lse - lse_ref).max() < 1e-12

    # Cascade / shared-prefix: 8 requests, one 1024-token shared prefix, 64 private tokens each.
    hq, hkv, d = 8, 2, 64
    kp, vp = rng.standard_normal((hkv, 1024, d)), rng.standard_normal((hkv, 1024, d))
    worst = 0.0
    for r in range(8):
        qr = rng.standard_normal((hq, 1, d))
        ks, vs = rng.standard_normal((hkv, 64, d)), rng.standard_normal((hkv, 64, d))
        ref, _ = naive_attention(qr, np.concatenate([kp, ks], 1), np.concatenate([vp, vs], 1))
        got, _ = merge_states([flash_attention_fwd(qr, kp, vp), flash_attention_fwd(qr, ks, vs)])
        worst = max(worst, np.abs(got - ref).max())
    print(f"cascade (shared prefix + private suffix) max|err|={worst:.2e}; "
          f"prefix KV read 1x instead of 8x")
    assert worst < 1e-12

    with np.errstate(over="ignore", invalid="ignore"):
        s16 = np.array([12.0, 11.0, -3.0], dtype=np.float16)
        e = np.exp(s16)
        unsafe = e / e.sum()
        safe = np.exp(s16 - s16.max())
        safe = safe / safe.sum()
    print(f"fp16 softmax of [12, 11, -3]: no max-subtraction -> {unsafe}; safe -> {safe}")
    assert np.isnan(unsafe).any() and np.isfinite(safe).all()

    o32, _ = flash_attention_fwd(*(rng.standard_normal(s).astype(np.float32)
                                   for s in ((8, 512, 128), (8, 512, 128), (8, 512, 128))), causal=True)
    assert o32.dtype == np.float32

    print("\n== HBM traffic, forward, N=8192, d=128, 64 heads (one Llama-3-70B layer), BF16, Br=128 ==")
    t = hbm_bytes(8192, 128, 64, 128)
    for name, b in t.items():
        print(f"  {name:20s} {b / 2**30:8.2f} GiB   at 3.35 TB/s: {b / 3.35e12 * 1e3:7.2f} ms")
    flops = 4 * 8192 * 8192 * 128 * 64
    print(f"  attention FLOPs {flops / 1e12:.2f} TFLOP -> {flops / 989.4e12 * 1e3:.2f} ms at BF16 peak")
    print(f"  materialized S for ONE head at N=131072, fp32: {131072**2 * 4 / 2**30:.0f} GiB")

    print("\n== SRAM / register budget per CTA (H100: 227 KiB smem per CTA, 255 regs/thread) ==")
    for br, bc, d, stages in ((128, 128, 128, 2), (128, 176, 128, 2), (128, 128, 128, 3),
                              (128, 80, 256, 2), (64, 64, 64, 2)):
        sm = smem_bytes(br, bc, d, stages)
        regs = accum_regs_per_thread(64, bc, d)
        print(f"  Br={br:3d} Bc={bc:3d} d={d:3d} stages={stages}: smem {sm / 1024:6.1f} KiB "
              f"{'OK ' if sm <= 227 * 1024 else 'TOO BIG'}  fp32 accum regs/thread (64 rows/WG) {regs:5.0f}")
    print("\nall FlashAttention reference self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified):

```text
FA2 Hq= 8 Hkv=8 Lq= 256 Lk= 256 d= 64 causal=True  Br=64 Bc=64: max|err|=1.11e-15
FA2 Hq= 8 Hkv=2 Lq= 200 Lk= 200 d= 64 causal=True  Br=64 Bc=48: max|err|=1.33e-15
FA2 Hq= 8 Hkv=2 Lq=  96 Lk= 480 d= 64 causal=True  Br=32 Bc=64: max|err|=1.78e-15
FA2 Hq=16 Hkv=2 Lq=   1 Lk=1000 d=128 causal=False Br=64 Bc=128: max|err|=8.88e-16
FA2 Hq= 4 Hkv=1 Lq= 130 Lk= 130 d= 32 causal=False Br=64 Bc=64: max|err|=9.99e-16
Flash-Decoding splits= 1: max|err|=2.08e-16
Flash-Decoding splits= 4: max|err|=2.08e-16
Flash-Decoding splits=16: max|err|=3.19e-16
Flash-Decoding splits=64: max|err|=5.69e-16
cascade (shared prefix + private suffix) max|err|=3.05e-16; prefix KV read 1x instead of 8x
fp16 softmax of [12, 11, -3]: no max-subtraction -> [nan  0.  0.]; safe -> [7.310e-01 2.688e-01 2.384e-07]

== HBM traffic, forward, N=8192, d=128, 64 heads (one Llama-3-70B layer), BF16, Br=128 ==
  naive                   32.50 GiB   at 3.35 TB/s:   10.42 ms
  flash, no L2 reuse      16.25 GiB   at 3.35 TB/s:    5.21 ms
  flash, ideal L2          0.50 GiB   at 3.35 TB/s:    0.16 ms
  attention FLOPs 2.20 TFLOP -> 2.22 ms at BF16 peak
  materialized S for ONE head at N=131072, fp32: 64 GiB

== SRAM / register budget per CTA (H100: 227 KiB smem per CTA, 255 regs/thread) ==
  Br=128 Bc=128 d=128 stages=2: smem  160.0 KiB OK   fp32 accum regs/thread (64 rows/WG)   128
  Br=128 Bc=176 d=128 stages=2: smem  208.0 KiB OK   fp32 accum regs/thread (64 rows/WG)   152
  Br=128 Bc=128 d=128 stages=3: smem  224.0 KiB OK   fp32 accum regs/thread (64 rows/WG)   128
  Br=128 Bc= 80 d=256 stages=2: smem  224.0 KiB OK   fp32 accum regs/thread (64 rows/WG)   168
  Br= 64 Bc= 64 d= 64 stages=2: smem   40.0 KiB OK   fp32 accum regs/thread (64 rows/WG)    64

all FlashAttention reference self-checks passed
```

### 4.3 Java 21: a TP-aware, overflow-proof KV sizer for the control plane

The Java control plane (gateway admission, autoscaler, cost model) needs the same arithmetic. The listing uses a
**sealed interface** of attention layouts with **record patterns** in an exhaustive `switch`, so adding a new layout
fails compilation until every pricing path handles it. It contrasts `naiveKvBytes(int...)`, which returns 0 for 128K,
with `Math.multiplyExact` long arithmetic. It also models TP replication for GQA and MLA, DP-attention capacity, and
whole-block rounding.

```java
// KvCacheSizer.java - Java 21 KV-cache sizing for MHA/GQA/MQA/MLA, TP-aware, block-rounded.
// Used by a gateway/control plane to price requests and plan replica capacity.
// Build & self-test:  javac --release 21 -Xlint:all -Werror -d out KvCacheSizer.java
//                     java -ea -cp out dev.l7.ai.inference.KvCacheSizer
package dev.l7.ai.inference;

import java.util.Map;

public final class KvCacheSizer {

    private KvCacheSizer() {}

    /** How a layer stores K/V for one token. Sealed: the switch below is checked for exhaustiveness. */
    public sealed interface KvLayout permits Gqa, Mla {}

    /** MHA (kvHeads == qHeads), GQA (1 < kvHeads < qHeads) and MQA (kvHeads == 1). */
    public record Gqa(int kvHeads, int kHeadDim, int vHeadDim) implements KvLayout {
        public Gqa {
            if (kvHeads <= 0 || kHeadDim <= 0 || vHeadDim <= 0) throw new IllegalArgumentException("non-positive dim");
        }
    }

    /** DeepSeek MLA: one compressed latent (kvLoraRank) + one decoupled RoPE key, shared by all heads. */
    public record Mla(int kvLoraRank, int ropeDim) implements KvLayout {}

    public record ModelGeometry(String name, int layers, int qHeads, KvLayout kv) {
        public long elemsPerTokenPerLayer() {
            return switch (kv) {
                case Gqa(int h, int dk, int dv) -> (long) h * (dk + dv);
                case Mla(int rank, int rope) -> (long) rank + rope;
            };
        }

        public long bytesPerToken(int bytesPerElem) {
            return Math.multiplyExact(Math.multiplyExact((long) layers, elemsPerTokenPerLayer()), bytesPerElem);
        }

        public String kind() {
            return switch (kv) {
                case Mla m -> "MLA";
                case Gqa g when g.kvHeads() == qHeads -> "MHA";
                case Gqa g when g.kvHeads() == 1 -> "MQA";
                case Gqa g -> "GQA-" + (qHeads / g.kvHeads());
            };
        }
    }

    /** Build from the handful of config.json fields that determine the cache. */
    public static ModelGeometry fromHfConfig(String name, Map<String, Integer> c) {
        int layers = c.get("num_hidden_layers");
        int heads = c.get("num_attention_heads");
        if (c.containsKey("kv_lora_rank")) {
            return new ModelGeometry(name, layers, heads, new Mla(c.get("kv_lora_rank"), c.get("qk_rope_head_dim")));
        }
        int headDim = c.getOrDefault("head_dim", c.get("hidden_size") / heads);
        return new ModelGeometry(name, layers, heads,
                new Gqa(c.getOrDefault("num_key_value_heads", heads), headDim, headDim));
    }

    public static final ModelGeometry LLAMA3_70B = fromHfConfig("Llama-3-70B", Map.of(
            "num_hidden_layers", 80, "num_attention_heads", 64, "num_key_value_heads", 8, "hidden_size", 8192));
    public static final ModelGeometry DEEPSEEK_V3 = fromHfConfig("DeepSeek-V3", Map.of(
            "num_hidden_layers", 61, "num_attention_heads", 128, "hidden_size", 7168,
            "kv_lora_rank", 512, "qk_rope_head_dim", 64));
    public static final ModelGeometry DEEPSEEK_V3_AS_MHA =
            new ModelGeometry("DeepSeek-V3 as MHA", 61, 128, new Gqa(128, 192, 128));

    // ------------------------------------------------------------------ the naive way

    /** The formula from the whiteboard, typed with ints. Compiles cleanly and returns garbage. */
    @SuppressWarnings("NumericOverflow")
    public static int naiveKvBytes(int layers, int kvHeads, int headDim, int seqLen, int batch, int bytes) {
        return 2 * layers * kvHeads * headDim * seqLen * batch * bytes;
    }

    // ------------------------------------------------------------------ the hardened way

    public enum AttentionParallelism { TENSOR, DATA }

    /** Bytes per token held by ONE rank, and how many copies of each byte exist across the group. */
    public record RankFootprint(long bytesPerTokenPerRank, int replication) {}

    public static RankFootprint perRank(ModelGeometry m, int tp, AttentionParallelism mode, int bytesPerElem) {
        long total = m.bytesPerToken(bytesPerElem);
        if (mode == AttentionParallelism.DATA) return new RankFootprint(total, 1);   // each rank owns its sequences
        return switch (m.kv()) {
            case Mla mla -> new RankFootprint(total, tp);    // latent is head-shared: every TP rank keeps it all
            case Gqa(int h, int dk, int dv) -> {
                int perRankHeads = Math.max(1, h / tp);     // tp > kvHeads -> heads are replicated
                long b = Math.multiplyExact((long) m.layers() * perRankHeads * (dk + dv), bytesPerElem);
                yield new RankFootprint(b, (int) (b * tp / total));
            }
        };
    }

    /** Exact paged reservation: whole blocks, never a partial one (vLLM/SGLang allocate per block). */
    public static long blocksFor(long tokens, int blockSize) { return Math.ceilDiv(tokens, blockSize); }

    /**
     * How many sequences of {@code contextTokens} fit in {@code freeBytesPerRank} of KV memory.
     * Under TP every rank holds a slice of every sequence; under DP-attention each rank holds whole
     * sequences, so the group's capacity is {@code ranks *} the per-rank answer.
     */
    public static long maxConcurrentSequences(ModelGeometry m, long freeBytesPerRank, long contextTokens, int ranks,
                                              AttentionParallelism mode, int blockSize, int bytesPerElem) {
        RankFootprint f = perRank(m, ranks, mode, bytesPerElem);
        long blockBytes = Math.multiplyExact(f.bytesPerTokenPerRank(), blockSize);
        long blocksPerRank = freeBytesPerRank / blockBytes;
        long perSeq = blocksFor(contextTokens, blockSize);
        long seqsPerRank = blocksPerRank / perSeq;
        return mode == AttentionParallelism.DATA ? seqsPerRank * ranks : seqsPerRank;
    }

    // ------------------------------------------------------------------ self-test

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) {
        ModelGeometry l70 = LLAMA3_70B;
        check(l70.bytesPerToken(2) == 327_680L, "Llama-3-70B 320 KiB/token");
        check(DEEPSEEK_V3.bytesPerToken(2) == 70_272L, "DeepSeek-V3 MLA 70,272 B/token");
        check(DEEPSEEK_V3_AS_MHA.bytesPerToken(2) == 4_997_120L, "MHA counterfactual");
        System.out.printf("%s [%s] %,d B/token; %s [%s] %,d B/token; MHA counterfactual %,d (%.1fx)%n",
                l70.name(), l70.kind(), l70.bytesPerToken(2), DEEPSEEK_V3.name(), DEEPSEEK_V3.kind(),
                DEEPSEEK_V3.bytesPerToken(2), DEEPSEEK_V3_AS_MHA.bytesPerToken(2),
                (double) DEEPSEEK_V3_AS_MHA.bytesPerToken(2) / DEEPSEEK_V3.bytesPerToken(2));

        int naive = naiveKvBytes(80, 8, 128, 131_072, 1, 2);
        long exact = Math.multiplyExact(l70.bytesPerToken(2), 131_072L);
        System.out.printf("naive int KV bytes for 1 x 128K: %d  (exact: %,d = 40 GiB)%n", naive, exact);
        check(naive == 0 && exact == 40L << 30, "the int formula wraps to exactly zero");
        try {
            Math.multiplyExact(2 * 80 * 8 * 128, 131_072);   // int overload: throws instead of wrapping
            check(false, "should have thrown");
        } catch (ArithmeticException expected) {
            System.out.println("Math.multiplyExact(int,int) -> ArithmeticException: " + expected.getMessage());
        }

        RankFootprint tp16 = perRank(l70, 16, AttentionParallelism.TENSOR, 2);
        RankFootprint dsTp8 = perRank(DEEPSEEK_V3, 8, AttentionParallelism.TENSOR, 2);
        System.out.printf("Llama-3-70B TP=16: %,d B/token/rank x%d; DeepSeek-V3 TP=8: %,d B/token/rank x%d%n",
                tp16.bytesPerTokenPerRank(), tp16.replication(), dsTp8.bytesPerTokenPerRank(), dsTp8.replication());
        check(tp16.equals(new RankFootprint(40_960, 2)) && dsTp8.equals(new RankFootprint(70_272, 8)), "TP sharding");

        long free = 37_000_000_000L;   // ~37 GB of KV per H200 after FP8 weights + activations (approx.)
        long tpSeqs = maxConcurrentSequences(DEEPSEEK_V3, free, 32_768, 8, AttentionParallelism.TENSOR, 64, 2);
        long dpSeqs = maxConcurrentSequences(DEEPSEEK_V3, free, 32_768, 8, AttentionParallelism.DATA, 64, 2);
        System.out.printf("DeepSeek-V3 8xH200 @32K ctx: TP-attention %d seqs, DP-attention %d seqs%n", tpSeqs, dpSeqs);
        check(dpSeqs == 8 * tpSeqs && tpSeqs == 16, "DP attention multiplies MLA capacity by the group size");

        check(blocksFor(17, 16) == 2 && blocksFor(16, 16) == 1 && blocksFor(0, 16) == 0, "block rounding");
        System.out.println("all KvCacheSizer self-checks passed");
    }
}
```

Output (verified):

```text
Llama-3-70B [GQA-8] 327,680 B/token; DeepSeek-V3 [MLA] 70,272 B/token; MHA counterfactual 4,997,120 (71.1x)
naive int KV bytes for 1 x 128K: 0  (exact: 42,949,672,960 = 40 GiB)
Math.multiplyExact(int,int) -> ArithmeticException: integer overflow
Llama-3-70B TP=16: 40,960 B/token/rank x2; DeepSeek-V3 TP=8: 70,272 B/token/rank x8
DeepSeek-V3 8xH200 @32K ctx: TP-attention 16 seqs, DP-attention 128 seqs
all KvCacheSizer self-checks passed
```

---

## 5. Production failure modes and P99 debugging

### F1 · The capacity planner admits everything at 128K (integer overflow)

- **Symptom:** an admission controller or cost estimator lets long-context traffic through without limit. Then the
  engine preempts constantly or OOMs during the profiling run.
- **Signature:** unit tests pass at 4K/8K. Failures begin at context lengths where the product crosses $2^{31}$. For
  Llama-3-70B the int formula wraps to exactly **0** at 128K.
- **Root cause:** 32-bit arithmetic on a product of six factors.
- **Fix:** `long` + `Math.multiplyExact` (Java), checked arithmetic (Rust), Python ints. Assert against a table of
  known values (§4.1).
- **Prevention:** property tests that sweep context length to the model maximum.

### F2 · TP=16 for Llama-3-70B "for more KV capacity" yields almost none

- **Symptom:** doubling TP from 8 to 16 adds GPUs but barely changes the maximum batch.
- **Signature:** per-rank KV bytes per token stay at 40,960 (vs the expected 20,480). vLLM logs the replication of KV
  heads.
- **Root cause:** $TP > n_{kv}$ replicates each KV head ($n_{kv} = 8$). The extra 8 GPUs mostly hold weight shards plus
  **duplicate** KV, and cross-node all-reduces get added on top.
- **Fix:** keep $TP \le n_{kv}$. Scale capacity with data-parallel replicas, or with pipeline parallelism if the model
  does not fit.

### F3 · DeepSeek-V3 on TP=8: KV capacity is 8× smaller than the MLA paper promised

- **Symptom:** a 671B MoE that "has a tiny KV cache" supports only a handful of 32K-context users per node.
- **Signature:** per-GPU KV usage is identical on all 8 ranks for the same sequences.
- **Root cause:** an MLA latent belongs to every head, so TP replicates it on every rank (×8).
- **Fix:** DP attention (SGLang `--enable-dp-attention`, ⚠ verify the flag for your version) with EP for the MoE
  layers. The capacity math in §4.3 gives 16 vs 128 sequences at 32K.

### F4 · NaNs in FP16 inference after a "harmless" custom attention change

- **Symptom:** sporadic NaN logits or garbage tokens, often on long or adversarial prompts.
- **Signature:** attention logits ≥ ~11.1 in FP16 ($e^{11.1} > 65{,}504$). It appears only on the eager (non-fused)
  path.
- **Root cause:** softmax without max-subtraction, or accumulation of $\ell$ in FP16.
- **Fix:** fused kernels (FA2/FA3/FlashInfer) or SDPA. If you must hand-roll, subtract the max, accumulate in FP32, and
  prefer BF16 activations.

### F5 · OOM or a 4× slowdown at long context after a dependency bump

- **Symptom:** memory grows quadratically with prompt length, or throughput falls at ≥ 8K.
- **Signature:** in a profile, attention shows three kernels (matmul → softmax → matmul) instead of one fused kernel.
  Memory spikes of $N^2 \times 4 \times n_{\text{heads}}$ bytes appear.
- **Root cause:** the fused backend was not selected and the stack silently fell back to the math/eager path.
  Typical triggers: unsupported head dim, dtype (FP32), an arbitrary attention mask, or an old GPU arch.
- **Fix:** pin the attention backend explicitly (vLLM selects per platform; ⚠ check the backend selection logs for your
  version), and fail the deploy if the fused backend isn't active.
- **Prevention:** a startup self-test asserting the backend name and a long-context smoke test with a memory ceiling.

### F6 · FP8 KV cache regressed long-context accuracy, but short-context evals passed

- **Symptom:** retrieval-heavy RAG answers degrade after enabling FP8 KV, while chat quality looks unchanged.
- **Root cause:** key outlier channels saturate E4M3 under a single per-tensor scale, and errors accumulate across
  thousands of keys in the softmax.
- **Fix:** calibrated per-head or per-channel key scales, E4M3 with proper scales, or keep keys in BF16 and quantize
  only values. Gate rollout on needle-in-a-haystack and long-document QA evals.

### F7 · KV estimate off by 33% for a new model family

- **Symptom:** the planner under- or over-provisions a newly onboarded model.
- **Root cause:** `head_dim` was derived as `hidden_size / num_attention_heads` but the config specifies `head_dim`
  explicitly (e.g. 256 vs a derived 192). Or the model has sliding/global hybrid layers the planner ignores.
- **Fix:** derive geometry only from the explicit config fields, model hybrid layers, and assert against the engine's
  own reported block count at startup.

---

## 6. FAANG L7 bar-raiser Q&A chains

### Q1 · "32 concurrent users, 128K context each, Llama-3-70B. How many H100s just for KV?"

- **L5 answer:** "About 2.5 MB per token... so roughly 10 TB? We need a lot of GPUs."
- **Why L5 fails:** it uses an MHA formula ($n_h = 64$) for a GQA-8 model, an 8× overestimate, and never states bytes
  per element or what TP does.
- **L7 defense:**
  1. $\kappa = 2\cdot 80\cdot 8\cdot 128\cdot 2 = 327{,}680$ B/token (320 KiB).
  2. Per user that is 40 GiB, so 32 users need **1,280 GiB** of KV.
  3. One 8×H100 TP=8 replica holds ~1.36M tokens ≈ 414 GiB of KV after weights, which is 10 whole 128K sequences
     ($1{,}356{,}942 / 131{,}072 = 10.35$). Three replicas hold 30 users, two short. The honest answer is **four
     replicas (32 GPUs)**, or **three with FP8 KV** (20 sequences each).
  4. Then check the SLO. At 10 users × 128K per replica, the KV read is 10 × 40 GiB / (8 × 3.35 TB/s) ≈ **16 ms per
     step** before weights. Feasible.
  5. Recommend FP8 KV plus a dedicated long-context pool, and say what it costs (validate retrieval accuracy).

### Q2 · "GQA vs MLA: which would you pick for a new model, and what does it cost the serving stack?"

- **L5 answer:** "MLA has a smaller cache, so MLA."
- **Why L5 fails:** it ignores the RoPE decoupling, the two-regime kernel split, TP replication, and ecosystem cost.
- **L7 defense:**
  1. MLA stores 576 elements per token per layer vs 2,048 for GQA-8 at the same width: 3.6× smaller than GQA-8, and
     71× smaller than MHA for DeepSeek's dims.
  2. MLA decode intensity is ~242 FLOP/B vs 8, so attention approaches the compute roof. That turns speculative
     decoding and MTP from a byte win into a FLOP-bound design question.
  3. Costs: decoupled RoPE complexity; two attention implementations (absorbed decode, decompressed prefill);
     TP-replicated latents that force DP attention plus an MoE/EP boundary; fewer kernel options (FlashMLA, FlashInfer
     MLA, TRT-LLM) than for GQA; and harder KV quantization (a mixed latent plus RoPE part).
  4. Choose MLA when long context and decode economics dominate and the team can own the kernels. Choose GQA-8 for
     ecosystem breadth and simpler parallelism.

### Q3 · "FlashAttention does *more* FLOPs in the backward pass. How is it faster?"

- **L5 answer:** "It uses SRAM, which is faster."
- **Why L5 fails:** it doesn't quantify, and it misses that the win comes from changing which roof the kernel sits
  under.
- **L7 defense:**
  1. Standard attention moves $\Theta(N^2)$ bytes, intensity ≈ $d$, and its softmax kernel has intensity ~1. For one
     70B layer at 8K that is 32.5 GiB → 10.4 ms, memory-bound.
  2. FlashAttention moves $\Theta(N^2d^2/M)$, effectively $O(Nd)$ with L2 reuse (0.5 GiB). It is compute-bound at
     ~2.2 ms.
  3. The backward pass recomputes $S, P$ from $Q, K$ and the LSE. That is extra FLOPs at the compute roof instead of
     reading $N^2$ values at the memory roof.
  4. FA2's single final normalization and its Q-parallel grid matter because non-matmul FLOPs cost ~16× matmul FLOPs
     on A100. FA3 adds async producer/consumer pipelines and ping-pong scheduling because exp throughput (3.9 TFLOP/s)
     would otherwise cost ~50% of matmul time.
  5. Memory falls from $O(N^2)$ to $O(N)$, which is what makes 128K context physically possible (64 GiB per head for
     $S$).

### Q4 · "Design attention serving for 1M-token context."

- **L5 answer:** "Use a model with a 1M context window and FlashAttention."
- **Why L5 fails:** $10^6$ tokens × 320 KiB ≈ **305 GiB of KV per user** for a GQA-8 70B model, before any batching. Prefill of
  1M tokens is quadratic ($L \gg L_\times = 106$K, so attention dominates).
- **L7 defense:**
  1. **Bytes:** MLA-class or hybrid local/global architectures (§2.7) plus FP8 KV. Then a hierarchical cache (HBM ←
     host DRAM ← NVMe, LMCache / Mooncake-style, Folder 02) with prefetching by layer.
  2. **Prefill FLOPs:** context parallelism (ring attention, merging states across devices) and prefix caching of the
     shared corpus. Treat it as a job, with TTFT SLOs in seconds.
  3. **Decode:** split-KV kernels to fill SMs. Every step must read all KV, so pricing per token per step makes
     per-user tokens/s fundamentally low. Charge for it.
  4. **Product:** question whether retrieval (Folder 04) can cut the context to 32K. That is usually the
     principal-level answer.

### Q5 · "Why not just quantize the KV cache to INT4 everywhere?"

- **L5 answer:** "4× smaller, more users. Ship it."
- **Why L5 fails:** it ignores error accumulation over long contexts, key outlier channels, dequant cost in the decode
  kernel, and which tasks degrade first.
- **L7 defense:**
  1. Quantize keys per channel and values per token (KIVI), or rotate first.
  2. Keep recent tokens and attention sinks in higher precision.
  3. Ensure the decode kernel dequantizes in registers. Otherwise you trade bandwidth for ALU and lose the gain at the
     MLA-like intensities where attention nears the compute roof.
  4. Gate on long-context retrieval evals, and roll out per tenant with A/B quality monitoring.
  5. Typically FP8 is the production default and INT4 a tier for cost-sensitive long-context traffic.

### Q6 · "FlashAttention for decode: what's wrong with just calling the prefill kernel with $L_q = 1$?"

- **L5 answer:** "It works, it's the same math."
- **Why L5 fails:** the math is the same, the parallelism is not. One Q tile means one CTA per (sequence, head). At
  small batch the GPU is mostly idle, and each CTA walks the whole context serially.
- **L7 defense:** use split-KV (Flash-Decoding) with the split count chosen so CTAs ≥ ~2× the SM count, plus the LSE
  merge. Use a paged-KV layout (File 03), GQA-aware loading (load one KV head per group, reuse it across $g$ query
  heads in registers), and CUDA graphs per batch bucket. For shared prefixes use cascade attention. The reference
  implementation verifies each identity.

### Q7 · "Someone proposes TP=16 to fit a 128K context for Llama-3-70B. Respond."

- **L5 answer:** "More GPUs, more memory, so yes."
- **Why L5 fails:** KV heads replicate past $TP = 8$, the all-reduces cross nodes, and capacity per GPU doesn't
  improve.
- **L7 defense:** per-rank KV stays 40,960 B/token (×2 replication). Cross-node all-reduce adds latency to every layer
  of every step. Alternatives: (a) two TP=8 replicas with context-length-aware routing; (b) FP8 KV, which doubles
  capacity in place; (c) pipeline parallelism across nodes for *weights* only, if needed; (d) KV offload tiers for cold
  sequences. Show the bytes.

---

## 7. Invariants checklist

- [ ] KV geometry comes from explicit config fields (`num_key_value_heads`, `head_dim`, `kv_lora_rank`,
      `qk_rope_head_dim`, `sliding_window` + layer pattern), never from `hidden_size / heads` alone.
- [ ] KV math is 64-bit and checked (`Math.multiplyExact`), with regression tests at the model's maximum context.
- [ ] Per-rank KV accounts for TP replication when $TP > n_{kv}$ and for **MLA under TP** (×TP).
- [ ] Hybrid/windowed models are sized per layer group, and the allocator knows the window.
- [ ] FP8/INT KV quantization is gated on long-context retrieval evals; keys per channel, values per token.
- [ ] A fused attention backend (FA2/FA3/FlashInfer/FlashMLA) is asserted at startup; eager fallback fails the deploy.
- [ ] Decode uses split-KV/paged kernels. Shared prefixes use cascade/prefix-aware attention.
- [ ] Softmax implementations subtract the running max and accumulate in FP32.

## 8. References

1. A. Vaswani et al. *Attention Is All You Need.* NeurIPS 2017.
2. N. Shazeer. *Fast Transformer Decoding: One Write-Head is All You Need.* arXiv:1911.02150, 2019.
3. J. Ainslie et al. *GQA: Training Generalized Multi-Query Transformer Models from Multi-Head Checkpoints.* EMNLP 2023.
4. DeepSeek-AI. *DeepSeek-V2: A Strong, Economical, and Efficient Mixture-of-Experts Language Model.* arXiv:2405.04434,
   2024 (§2.1 MLA).
5. DeepSeek-AI. *DeepSeek-V3 Technical Report.* arXiv:2412.19437, 2024. FlashMLA repository (deepseek-ai/FlashMLA).
6. M. Milakov, N. Gimelshein. *Online normalizer calculation for softmax.* arXiv:1805.02867, 2018.
7. M. Rabe, C. Staats. *Self-attention Does Not Need O(n²) Memory.* arXiv:2112.05682, 2021.
8. T. Dao, D. Fu, S. Ermon, A. Rudra, C. Ré. *FlashAttention: Fast and Memory-Efficient Exact Attention with
   IO-Awareness.* NeurIPS 2022.
9. T. Dao. *FlashAttention-2: Faster Attention with Better Parallelism and Work Partitioning.* ICLR 2024.
10. J. Shah, G. Bikshandi, Y. Zhang, V. Thakkar, P. Ramani, T. Dao. *FlashAttention-3: Fast and Accurate Attention with
    Asynchrony and Low-precision.* NeurIPS 2024.
11. T. Dao, D. Haziza, F. Massa, G. Sizov. *Flash-Decoding for long-context inference.* PyTorch/Together blog, 2023.
12. Z. Ye et al. *FlashInfer: Efficient and Customizable Attention Engine for LLM Inference Serving.* MLSys 2025; and
    *Cascade Inference* (FlashInfer blog, 2024).
13. J. Juravsky et al. *Hydragen: High-Throughput LLM Inference with Shared Prefixes.* arXiv:2402.05099, 2024.
14. H. Liu, M. Zaharia, P. Abbeel. *Ring Attention with Blockwise Transformers for Near-Infinite Context.* 2023.
15. A. Jiang et al. *Mistral 7B.* arXiv:2310.06825, 2023 (sliding window, rolling buffer cache).
16. Z. Liu et al. *KIVI: A Tuning-Free Asymmetric 2bit Quantization for KV Cache.* ICML 2024. C. Hooper et al.
    *KVQuant.* NeurIPS 2024.
