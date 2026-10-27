# 01 · The Roofline Model: Why Prefill Is Compute-Bound and Decode Is Memory-Bound

> **Folder:** `01-LLM-Inference-Physics-and-KV-Cache/` · **File 1 of 3**
> **Anchoring papers:** Williams, Waterman & Patterson, *Roofline: An Insightful Visual Performance Model for Multicore
> Architectures* (CACM 2009) · Kaplan et al., *Scaling Laws for Neural Language Models* (2020; the "2N FLOPs per token"
> rule) · Pope et al., *Efficiently Scaling Transformer Inference* (MLSys 2023) · Yu et al., *Orca* (OSDI 2022) · Kwon et
> al., *PagedAttention / vLLM* (SOSP 2023) · Agrawal et al., *Sarathi-Serve* (OSDI 2024) · DeepSeek-AI, *DeepSeek-V3
> Technical Report* (2024) · Frantar et al., *MARLIN: Mixed-Precision Auto-Regressive Parallel Inference* (2024).
> **Code baseline:** Python 3.10+ (verified on CPython 3.14.5, NumPy 2.5.4) · Java 21 (compiled with JDK 25.0.4,
> `javac --release 21 -Xlint:all -Werror`).
> **Next:** [02 · KV cache math: MHA, GQA, MLA, and FlashAttention SRAM tiling](02-kv-cache-math-mha-gqa-mla-and-flashattention-sram-tiling.md)

---

## 0. The thesis in one paragraph

Transformer inference is two different workloads that share one set of weights. **Prefill** pushes the whole prompt
through the network at once. Every weight byte loaded from HBM is reused across thousands of prompt tokens, so the
linear layers are matrix-matrix products (GEMMs) whose arithmetic intensity is far above the GPU's ridge point. Prefill
is **compute-bound**, and it sets time-to-first-token (TTFT). **Decode** emits one token per sequence per step. Every
weight byte is loaded to do one multiply-add *per sequence in the batch*, so the linear layers are matrix-vector
products (GEMVs) whose intensity equals the batch size. Decode is **memory-bandwidth-bound**, and it sets inter-token
latency (ITL, also called TPOT). Batching is the only lever that turns decode's GEMV back into a GEMM. The KV cache
caps how far that lever goes: it is private to each sequence, it grows with context, and batching never amortizes it.
Continuous batching, chunked prefill, prefill/decode disaggregation, GQA/MLA, FP8, speculative decoding, and prefix
caching are all moves on the chart this file builds. An L7 engineer prices each of them in FLOPs and bytes before
running a benchmark.

---

## 1. The roofline model from first principles

### 1.1 Two roofs and a ridge

A kernel performs $F$ floating-point operations and moves $Q$ bytes between DRAM (HBM on a GPU) and the chip. Its
**arithmetic intensity** is

$$
I \;=\; \frac{F}{Q}\quad\left[\frac{\text{FLOP}}{\text{byte}}\right].
$$

With peak compute $P_{\text{peak}}$ (FLOP/s) and peak memory bandwidth $B$ (byte/s), the attainable throughput is

$$
P_{\text{attainable}}(I) \;=\; \min\!\left(P_{\text{peak}},\; I \cdot B\right),
\qquad
t_{\text{kernel}} \;\ge\; \max\!\left(\frac{F}{P_{\text{peak}}},\; \frac{Q}{B}\right).
$$

The two roofs meet at the **ridge point**

$$
I^{*} \;=\; \frac{P_{\text{peak}}}{B}.
$$

A kernel with $I < I^{*}$ is **memory-bound**: buying more FLOP/s does nothing, and only fewer bytes or more bandwidth
help. A kernel with $I > I^{*}$ is **compute-bound**: shaving bytes does nothing, and only fewer FLOPs, lower
precision, or more tensor-core throughput help. The $\max(\cdot)$ is a *lower bound* that assumes perfect overlap of
compute and memory traffic. Real kernels sit between $\max$ and the sum, and a well-pipelined kernel (TMA plus warp
specialization on Hopper) approaches $\max$.

> **Rule of thumb that is actually a theorem:** the roofline must be applied *per kernel*, never to a whole forward
> step. A decode step contains GEMMs whose intensity grows with batch size and an attention kernel whose intensity does
> **not**. Averaging them hides the bottleneck (§1.6).

### 1.2 The hardware numbers

Always use **dense** tensor-core numbers. Spec sheets headline 2:4-structured-sparsity figures, which are 2× higher, and
no production LLM serving stack runs sparse GEMMs.

| GPU | BF16 dense | FP8 dense | HBM BW | HBM | Ridge BF16 | Ridge FP8 | Intra-node link |
|-----|-----------:|----------:|-------:|----:|-----------:|----------:|-----------------|
| A100-SXM4-80GB | 312 TFLOP/s | — | 2.039 TB/s | 80 GB HBM2e | **153** | — | NVLink3 600 GB/s (bidir.) |
| H100-SXM5-80GB | 989.4 TFLOP/s | 1,978.9 TFLOP/s | 3.35 TB/s | 80 GB HBM3 | **295** | **591** | NVLink4 900 GB/s (bidir.) |
| H200-SXM-141GB | 989.4 TFLOP/s | 1,978.9 TFLOP/s | 4.8 TB/s | 141 GB HBM3e | **206** | **412** | NVLink4 900 GB/s |
| B200-SXM (⚠ SKU-dependent) | ~2,250 TFLOP/s | ~4,500 TFLOP/s | 8.0 TB/s | ~180 GB HBM3e | **~281** | **~562** | NVLink5 1.8 TB/s |
| L40S-48GB | 362 TFLOP/s | 733 TFLOP/s | 0.864 TB/s | 48 GB GDDR6 | **419** | **848** | PCIe Gen4 only |

The ridge points are printed by `roofline.py` (§3.2). Three things in this table drive real procurement decisions:

1. **H100 → H200 changes only memory.** The compute is identical. Bandwidth goes up 1.43× and capacity 1.76×. For a
   decode-bound fleet that is the whole upgrade. For a prefill-bound fleet it is close to nothing (§4, F1).
2. **The ridge moves *down* from H100 to H200** (295 → 206). More of the workload becomes compute-bound on H200
   because bytes got cheaper relative to FLOPs.
3. **L40S has the highest ridge** (419). Its GDDR6 is 4× slower than H100's HBM3, so decode at small batch is
   painfully slow, but the part is cost-effective for prefill-heavy or embedding workloads (§4, Q2).

### 1.3 The memory hierarchy a kernel actually sees (H100 SXM5)

```
                     capacity            bandwidth (aggregate)          latency (order of magnitude)
  ┌──────────────┐
  │ Registers    │   256 KiB / SM        (feeds tensor cores directly)   ~1 cycle
  │ (64K x 32b)  │   = 33 MiB total
  ├──────────────┤
  │ SMEM / L1    │   256 KiB / SM        ~33 TB/s  (128 B/clk/SM)        ~30 cycles
  │ (≤228 KiB    │   (≤227 KiB per CTA)  ← FlashAttention tiles live here
  │  as SMEM)    │
  ├──────────────┤
  │ L2           │   50 MiB              several TB/s (⚠ not published)  ~200-300 cycles
  ├──────────────┤
  │ HBM3         │   80 GiB              3.35 TB/s                       ~500-800 cycles
  │ (5 stacks)   │   ← weights, KV cache, activations
  ├──────────────┤
  │ NVLink4      │   peer GPU HBM        450 GB/s per direction          µs
  ├──────────────┤
  │ PCIe Gen5x16 │   host DRAM           ~64 GB/s per direction          µs
  ├──────────────┤
  │ NVMe / RDMA  │   TBs                 3-14 GB/s per drive; 50 GB/s per 400G NIC   10s of µs
  └──────────────┘
```

Each step down is roughly an order of magnitude less bandwidth. LLM inference engineering is the craft of making the
dominant data stream (weights, KV, or activations) live at the highest level it fits in, and reusing every byte as
many times as possible before evicting it.

### 1.4 Arithmetic intensity of a GEMM, derived

A linear layer computes $Y_{[m\times n]} = X_{[m\times k]} \, W_{[k\times n]}$. Here $m$ is the number of tokens in
the step, $k$ the input width, and $n$ the output width. Assume each operand is read once and the output written once,
which is ideal reuse. Let $b_a$ be the bytes per activation element and $b_w$ the bytes per weight element:

$$
F = 2mkn, \qquad Q = b_a\,mk + b_w\,kn + b_a\,mn,
\qquad
I(m) = \frac{2mkn}{b_a\,mk + b_w\,kn + b_a\,mn}.
$$

**Small $m$ (decode).** When $m \ll k, n$ the weight term dominates $Q$:

$$
I(m) \;\approx\; \frac{2mkn}{b_w\,kn} \;=\; \frac{2m}{b_w}
\;\;\xrightarrow{\;b_w = 2\ (\text{BF16})\;}\;\; I \approx m .
$$

**In BF16, decode GEMM intensity equals the number of tokens in the batch.** At batch 1 it is 1 FLOP/byte, which is
295× below the H100 ridge. The tensor cores idle more than 99% of the time.

**Large $m$ (prefill).** As $m \to \infty$, $I \to 2kn / (b_a(k+n))$. For $k=n=8192$ in BF16 that is 4,096 FLOP/byte,
14× above the ridge.

**The critical batch.** Setting $I(m) = I^{*}$ and solving for $m$:

$$
m^{*} \;=\; \frac{I^{*}\, b_w\, k\, n}{2kn - I^{*} b_a (k+n)} .
$$

| Shape (BF16 unless noted) | $m^{*}$ on H100 | Meaning |
|---------------------------|----------------:|---------|
| $k=n=8192$ (Llama-3-70B `o_proj`, TP=1) | **318.3** tokens | Below this many tokens per step, the layer is memory-bound |
| $k=8192,\ n=1280$ (fused QKV shard at TP=8) | **402.8** tokens | Sharding makes GEMMs skinnier, so activation traffic is a larger share of bytes and the knee moves right |
| $k=n=8192$, W4A16 ($b_w=0.5$) | **79.6** tokens | INT4 weights move the knee left 4×. Past it, dequantization ALU work is pure overhead |

The full intensity sweep (from `roofline.py`):

| $m$ | 1 | 8 | 64 | 256 | 318 | 512 | 2,048 | 8,192 |
|-----|--:|--:|---:|----:|----:|----:|------:|------:|
| $I(m)$ FLOP/B, $k=n=8192$ | 1.00 | 7.98 | 63.0 | 240.9 | **295.1** | 455.1 | **1,365.3** | 2,730.7 |

### 1.5 Prefill is compute-bound: the proof

During prefill $m = L_{\text{prompt}}$. For a 2,048-token prompt through an $8192 \times 8192$ projection:

$$
I(2048) = \frac{2048 \cdot 8192 \cdot 8192}{2048\cdot 8192 + 8192^2 + 2048 \cdot 8192}\cdot\frac{2}{2}
= \frac{2048 \cdot 8192}{2048 + 8192 + 2048} = \frac{16{,}777{,}216}{12{,}288} = 1365.3\ \tfrac{\text{FLOP}}{\text{B}} \gg 295 .
$$

Every linear layer in prefill is compute-bound by 4.6× or more. **Attention in prefill** is compute-bound too.
FlashAttention reads $Q,K,V$ and writes $O$ in $O(L\,d)$ bytes while doing $O(L^2 d)$ FLOPs (File 02). Its causal
FLOPs per sequence are

$$
F_{\text{attn}}^{\text{prefill}} = 2\, n_{\text{layers}}\, n_{\text{heads}}\, d_{\text{head}}\, L^2
\quad(\text{QK}^\top\text{ and PV, half the square masked}),
\qquad
F_{\text{GEMM}}^{\text{prefill}} = 2 P L ,
$$

where $P$ is the number of streamed (non-embedding) parameters. The two are equal at

$$
L_{\times} = \frac{P}{n_{\text{layers}}\, n_{\text{heads}}\, d_{\text{head}}}
= \frac{69.50\times 10^{9}}{80 \cdot 64 \cdot 128} = 106{,}051 \text{ tokens (Llama-3-70B)}.
$$

Below ~106K tokens the MLPs and projections dominate prefill. Above it, attention's quadratic term takes over. Measured
by the model (8×H100, TP=8, 50% MFU on compute-bound kernels):

| Prompt | Prefill time (TTFT floor) | Attention share | TP all-reduce share |
|-------:|--------------------------:|----------------:|--------------------:|
| 8,192 | **411.7 ms** | 5% | **26% (106 ms)** |
| 32,768 | 1.91 s | 19% | — |
| 131,072 | 11.90 s | **48%** | — |

The 26% communication share at 8K is a real production effect. Every layer all-reduces an $L \times d$ activation
tensor twice: $8192 \times 8192 \times 2$ B = 128 MiB, 160 times per prefill. This is why high-TP prefill wants
sequence parallelism or compute–communication overlap, and why disaggregated prefill pools often run at lower TP than
decode pools (Folder 02).

### 1.6 Decode is memory-bound: the proof, including the part batching cannot fix

A decode step for $B$ sequences with cached contexts $L_1,\dots,L_B$ moves two kinds of bytes:

$$
Q_{\text{step}} \;=\; \underbrace{b_w P}_{\text{weights: once per step}}
\;+\; \underbrace{\kappa \textstyle\sum_{i=1}^{B} L_i}_{\text{KV cache: per sequence}},
\qquad
\kappa = 2\, n_{\text{layers}}\, n_{\text{kv}}\, d_{\text{head}}\, b_{kv}\ \ \text{(bytes/token, File 02)},
$$

and performs

$$
F_{\text{step}} \;=\; 2PB \;+\; 4\, n_{\text{layers}}\, n_{\text{heads}}\, d_{\text{head}} \textstyle\sum_i L_i .
$$

For a uniform context $L$, the whole-step intensity is

$$
I_{\text{step}}(B, L) = \frac{B\,(2P + 4 n_{\text{layers}} n_{\text{heads}} d_{\text{head}} L)}{b_w P + B L \kappa}
\;\;\xrightarrow{\;B \to \infty\;}\;\;
I_{\infty}(L) = \frac{2P + 4\, n_{\text{layers}}\, n_{\text{heads}}\, d_{\text{head}}\, L}{L\,\kappa}.
$$

**This limit is the most important equation in LLM serving.** Batching amortizes the weight bytes but never the KV bytes,
because each sequence's KV is private. For Llama-3-70B ($P_{\text{streamed}} = 69.50$ B, $\kappa = 327{,}680$ B/token):

$$
I_\infty(4096) = \frac{2(69.50\times10^9) + 4\cdot 80 \cdot 64 \cdot 128 \cdot 4096}{4096 \cdot 327{,}680}
= \frac{149.7\times 10^{9}}{1.342\times 10^{9}} = 111.6\ \tfrac{\text{FLOP}}{\text{B}},
\qquad I_\infty(32768) = 20.9 .
$$

Both are below H100's ridge of 295. **At 4K context, Llama-3-70B decode cannot become compute-bound on an H100 at any
batch size**, even with infinite memory. At 32K it is 14× below the ridge. The KV cache is the decode bottleneck, not
the weights.

The per-kernel view makes this sharper. The decode attention kernel has intensity

$$
I_{\text{attn}} = \frac{4\, n_{\text{heads}}\, d_{\text{head}}\, L}{2\, n_{\text{kv}}\, d_{\text{head}}\, L\, b_{kv}}
= \frac{2}{b_{kv}}\cdot\frac{n_{\text{heads}}}{n_{\text{kv}}}
\;\;\xrightarrow{\;\text{BF16}\;}\;\; g = \frac{n_{\text{heads}}}{n_{\text{kv}}}\ \ (\text{the GQA group size}),
$$

**independent of batch size and context length.** It is 8 FLOP/B for Llama-3-70B (GQA-8) and 1 FLOP/B for an MHA model.
For DeepSeek's MLA it is about 242 FLOP/B, because 128 query heads share one 576-wide latent (File 02, §2.4). The GEMMs
cross the ridge near $B \approx 300$. The attention kernel never does, unless the architecture raises $g$ (GQA → MLA)
or the step processes several query tokens per sequence (speculative decoding, Folder 02).

### 1.7 The numbers: Llama-3-70B on 8×H100 (TP=8, BF16)

From `roofline.py`, as a per-kernel roofline sum plus a ring all-reduce model (NCCL bus bandwidth 360 GB/s, 10 µs per
call). This is a **lower bound**: it ignores norms, RoPE, sampling, and launch overhead.

| Batch × context | Step (ITL floor) | GEMMs | KV read | TP comm | Step FLOP/B | tok/s/user | tok/s total |
|-----------------|-----------------:|------:|--------:|--------:|------------:|-----------:|------------:|
| 1 × 4,096 | **6.85 ms** | 5.19 ms | 0.05 ms | 1.61 ms | 1.1 | 145.9 | 146 |
| 64 × 4,096 | 10.95 ms | 5.33 ms | 3.21 ms | 2.42 ms | 41.9 | 91.3 | 5,846 |
| 256 × 4,096 | 23.43 ms | 5.75 ms | **12.82 ms** | 4.86 ms | 77.0 | 42.7 | 10,924 |
| 256 × 32,768 | **113.18 ms** | 5.75 ms | **102.57 ms** | 4.86 ms | 19.8 | 8.8 | 2,262 |

Read the rows as a story:

- **Batch 1:** the GEMMs stream 139 GB of weights for one token. The napkin formula
  $\text{BW}/\text{model bytes}$ gives 190 tok/s, but the model says 146. The gap is 160 all-reduces of 10 µs each
  (1.6 ms), which the napkin ignores.
- **Batch 1 → 64:** throughput rises 40× while ITL rises only 1.6×. This is why continuous batching exists (Folder 02).
- **Batch 256 at 4K:** the KV read (12.8 ms) has overtaken all the weight GEMMs combined (5.75 ms).
- **Same batch at 32K:** ITL grows 4.8× with no change in batch size. The weights didn't change and the KV bytes grew
  8×. A capacity plan expressed in "concurrent requests" without context length is meaningless (§4, F2).

**The throughput–latency frontier.** Throughput is $B / t_{\text{step}}(B)$. While weights dominate, $t_{\text{step}}$
is flat and throughput grows linearly in $B$. Once the KV term dominates, throughput saturates at

$$
\lim_{B\to\infty} \frac{B}{t_{\text{step}}} = \frac{TP \cdot B_{\text{HBM}}}{L\,\kappa}
= \frac{8 \cdot 3.35\times10^{12}}{4096 \cdot 327{,}680} \approx 19{,}966 \ \text{tok/s at 4K},
\qquad \approx 2{,}496 \ \text{tok/s at 32K}.
$$

HBM capacity binds before that asymptote. With `gpu_memory_utilization=0.9` and a 3 GiB activation reserve, the
8-GPU group holds **1,356,942 tokens** of KV (84,808 vLLM blocks of 16 tokens). That is 331 sequences at 4K, 41 at
32K, and 10 at 128K. An **ITL SLO of 20 ms caps the batch at 203** at 4K context. At 30 ms the capacity limit (331)
binds first.

### 1.8 MoE: why "37B active parameters" is a FLOPs metric, not a bytes metric

In a mixture-of-experts layer with $E$ routed experts and top-$k$ routing, a step with $B$ tokens sends on average
$m_e = Bk/E$ tokens to each expert. Each expert GEMM therefore has intensity $\approx 2m_e/b_w$. For the expert GEMMs to
reach the ridge:

$$
B \;\ge\; \frac{I^{*}\, b_w}{2}\cdot\frac{E}{k}
= \frac{295.3 \cdot 2}{2}\cdot\frac{256}{8} \approx 9{,}451 \ \text{tokens per step (DeepSeek-V3, H100, BF16)} .
$$

FP8 halves $b_w$ and doubles $I^{*}$, so the answer is the same 9,451. That is ~30× the dense critical batch. It is
the physical reason DeepSeek's production decode spreads routed experts over very wide expert parallelism. Their
published inference overview describes EP144 across 18 nodes for decode and EP32 for prefill (⚠ verify against the
DeepSeek "Inference System Overview", 2025). Wide EP aggregates enough tokens per expert per step to escape the memory
roof.

The bytes side is worse than the FLOPs side suggests. Under uniform, independent routing, the expected number of
*distinct* experts a step touches is

$$
\mathbb{E}[\text{experts touched}] = E\left(1 - \left(1 - \tfrac{k}{E}\right)^{B}\right),
$$

and **all** of their weights must be streamed:

| Tokens in step | Experts touched (of 256) | Share of routed-expert bytes streamed |
|---------------:|-------------------------:|--------------------------------------:|
| 1 | 8.0 | 3.1% |
| 8 | 57.4 | 22.4% |
| 32 | 163.3 | **63.8%** |
| 128 | 251.6 | 98.3% |
| 512 | 256.0 | 100% |

At a 32-token decode batch, a "37B active" model streams most of its 671B parameters every step while doing the FLOPs
of a 37B model. MoE serving is the most memory-bound workload in this file until the batch is huge.

### 1.9 Where the roofline lies (and what to add back)

| Ignored by the model | Size of the effect | What production does |
|----------------------|--------------------|----------------------|
| Kernel-launch / Python overhead | 80 layers × ~8–12 kernels × several µs ≈ **several ms** at batch 1, which rivals the 5 ms GEMM time | CUDA graphs captured per batch-size bucket; vLLM V1 runs the scheduler in a separate process from the GPU worker (⚠ verify capture sizes for your version) |
| Achievable vs spec bandwidth | Well-tuned GEMV/attention kernels reach roughly 80–90% of spec HBM BW (MBU) | Measure MBU = (bytes/step)/(step time × peak BW) and alert on regressions |
| Achievable vs spec FLOPs | Large BF16 GEMMs reach roughly 60–80% of dense peak; FA3 forward ~75% (File 02) | Use measured MFU per kernel in capacity plans, not spec |
| Skinny-GEMM kernel selection | Libraries tuned for big GEMMs fall well below the memory roof for $2 \le m \le 64$ (measured on this laptop in §2) | Dedicated decode kernels: split-K GEMV, Marlin (W4A16), FP8 GEMV paths |
| Small-message all-reduce latency | Dominates at TP=8, batch 1 (1.6 of 6.85 ms above) | Custom one-shot/two-shot NVLink all-reduce for small messages (vLLM ships one), NVLS/SHARP on NVSwitch |
| CPU-side sampling, detokenization, HTTP/SSE | Becomes the bottleneck for small models at high batch | Asynchronous output processing, separate API-server processes, batched detokenization |
| Power and clock throttling | Sustained tensor load can lower clocks below boost | Watch `DCGM_FI_DEV_SM_CLOCK` and power; derate peak FLOPs in plans |

---

## 2. Measured: the roofline on this laptop's CPU

GPU numbers in this file are analytic (no GPU was available while writing). But the physics is not GPU-specific. The
listing in §3.3 runs $Y = XW^\top$ with a fixed 64 MiB FP32 weight matrix on **one core** of an Intel Core i5-11260H. It
compares $m$ separate GEMVs (decode without batching) against one batched GEMM (continuous batching), and both against
the roofline built from the roofs it measures. Output from one measured run:

```text
W = 4096x4096 fp32 (64 MiB), 1 thread, best of 3
measured roofs: memory ~26.8 GB/s, compute ~95.5 GFLOP/s, ridge ~3.6 FLOP/B

   m  AI FLOP/B  unbatched   batched  roofline   (GFLOP/s)
   1       0.50       10.8      13.4      13.4
   2       1.00       13.0       7.4      26.8
   4       2.00       12.6      14.2      53.5
   8       3.98       12.4      26.1      95.5
  16       7.94       13.0      41.9      95.5
  32      15.75       12.9      61.8      95.5
  64      31.03       12.6      69.7      95.5
 128      60.24          -      89.2      95.5
 256     113.78          -      94.7      95.5
 512     204.80          -      95.5      95.5
```

What the run proves:

1. **Unbatched decode is flat.** About 11–13 GFLOP/s at every $m$, because every sequence re-streams all 64 MiB of
   weights. Throughput per sequence never improves, which is exactly the pre-Orca serving world.
2. **Batched GEMM climbs the memory roof, then hits the compute roof.** It goes from 13 GFLOP/s at $m=1$ to about
   95–102 GFLOP/s by $m \approx 256$, a 7× gain from reuse alone with the same silicon.
3. **The valley between them is real.** At $2 \le m \le 64$ the measured GEMM sits well *below* the memory roof. A
   general-purpose SGEMM packs and blocks for big matrices, and skinny shapes waste most of that work. The roofline is
   an upper bound, and reaching it for decode-shaped GEMMs requires purpose-built kernels. The weight layout matters too:
   a probe during writing showed `x @ W.T` (the `nn.Linear` layout) running about 2× faster than `x @ W` at small $m$.
4. The CPU's ridge is ~3.6–3.9 FLOP/B against H100's 295, so a CPU leaves the memory-bound regime at a tiny batch.
   The *shape* of the curve is the same.

---

## 3. Production code blueprints

### 3.1 The naive way: napkin capacity planning

This is the capacity model behind most first LLM deployments. Every line is a production incident:

```python
# napkin.py - DO NOT USE: every assumption below is wrong at scale
hbm_bw, n_gpus = 3.35e12, 8
model_bytes = 70.6e9 * 2                               # BF16 Llama-3-70B
tokens_per_s_per_user = n_gpus * hbm_bw / model_bytes  # (1) ignores KV reads, TP comms, launch overhead
max_concurrency = 256                                  # (2) a constant: tuned once at 2K-token prompts
kv_bytes = 2 * 80 * 8 * 128 * 131072 * 2               # (3) fine in Python; in Java/C int math this is 0 (File 02)
# (4) no ITL SLO anywhere: the planner cannot say "no" to a request that would slow everyone else down
```

What breaks:

1. It overstates batch-1 speed by 30% (190 vs 146 tok/s) and says nothing about batch > 1.
2. A static concurrency limit admits 6.2× more KV than exists once prompts grow to 32K (§3.4 output). The engine then
   preempts constantly (File 03).
3. It has no notion of context length, the variable that dominates decode cost.

### 3.2 The hardened way (Python): a per-kernel roofline estimator

`roofline.py` prices every GEMM of a Llama-style layer on one TP rank with Megatron sharding (KV heads replicated when
$TP > n_{kv}$). It also prices the decode attention KV read and the TP all-reduces, and derives KV capacity,
SLO-feasible batch, and MoE expert traffic. It is stdlib-only and every number in §1 comes from it.

```python
"""roofline.py - per-kernel roofline and LLM step-time estimator (Python 3.10+, stdlib only).

Every analytic number quoted in 01-roofline-model-prefill-compute-bound-vs-decode-memory-bound.md
is printed by `python roofline.py`. The model is a *lower bound*: it prices GEMMs, attention KV
reads and tensor-parallel all-reduces, and ignores norms, RoPE, sampling, and launch overhead.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

GiB = 2**30


@dataclass(frozen=True)
class Gpu:
    name: str
    bf16_flops: float   # dense tensor-core FLOP/s (no 2:4 sparsity)
    fp8_flops: float    # dense tensor-core FLOP/s; 0.0 if the part has no FP8 tensor cores
    hbm_bw: float       # bytes/s, spec-sheet peak
    hbm_bytes: float    # bytes visible to CUDA (approx.; varies by driver/ECC)
    ar_busbw: float     # effective NCCL all-reduce bus bandwidth inside one node, bytes/s
    ar_latency: float   # fixed cost per all-reduce call, seconds

    def peak(self, dtype: str) -> float:
        flops = self.fp8_flops if dtype == "fp8" else self.bf16_flops
        if flops <= 0:
            raise ValueError(f"{self.name} has no {dtype} tensor cores")
        return flops

    def ridge(self, dtype: str = "bf16") -> float:
        """Arithmetic intensity (FLOP/byte) where the HBM roof meets the compute roof."""
        return self.peak(dtype) / self.hbm_bw


A100 = Gpu("A100-SXM4-80GB", 312e12, 0.0, 2.039e12, 79.2 * GiB, 230e9, 10e-6)
H100 = Gpu("H100-SXM5-80GB", 989.4e12, 1978.9e12, 3.35e12, 79.1 * GiB, 360e9, 10e-6)
H200 = Gpu("H200-SXM-141GB", 989.4e12, 1978.9e12, 4.8e12, 139.8 * GiB, 360e9, 10e-6)
B200 = Gpu("B200-SXM-180GB", 2250e12, 4500e12, 8.0e12, 178.0 * GiB, 720e9, 10e-6)
L40S = Gpu("L40S-48GB", 362e12, 733e12, 0.864e12, 44.4 * GiB, 20e9, 20e-6)
GPUS = (A100, H100, H200, B200, L40S)


@dataclass(frozen=True)
class DenseModel:
    """A Llama-style decoder: fused QKV, SwiGLU MLP, untied LM head unless tied=True."""
    name: str
    d_model: int
    n_layers: int
    n_heads: int
    n_kv_heads: int
    head_dim: int
    d_ff: int
    vocab: int
    tied: bool = False

    @property
    def layer_params(self) -> int:
        attn = self.d_model * self.head_dim * (2 * self.n_heads + 2 * self.n_kv_heads)
        return attn + 3 * self.d_model * self.d_ff

    @property
    def streamed_params(self) -> int:
        """Weights every forward step must stream from HBM: all layers + LM head.
        The embedding table is a gather of B rows, not a GEMM, so it is excluded."""
        return self.n_layers * self.layer_params + self.vocab * self.d_model

    @property
    def total_params(self) -> int:
        return self.streamed_params + (0 if self.tied else self.vocab * self.d_model)

    def kv_bytes_per_token(self, kv_bytes: float = 2) -> float:
        return 2 * self.n_layers * self.n_kv_heads * self.head_dim * kv_bytes

    def attn_flops_per_token(self, ctx: int) -> float:
        """Decode attention FLOPs for ONE new token that attends to `ctx` cached tokens."""
        return 4.0 * self.n_layers * self.n_heads * self.head_dim * ctx


LLAMA3_8B = DenseModel("Llama-3-8B", 4096, 32, 32, 8, 128, 14336, 128256)
LLAMA3_70B = DenseModel("Llama-3-70B", 8192, 80, 64, 8, 128, 28672, 128256)


# --------------------------------------------------------------------------- GEMM roofline
def gemm_intensity(m: int, k: int, n: int, w_bytes: float = 2, a_bytes: float = 2) -> float:
    """FLOP/byte of Y[m,n] = X[m,k] @ W[k,n] with X/Y read/written once (perfect reuse)."""
    return (2.0 * m * k * n) / (a_bytes * m * k + w_bytes * k * n + a_bytes * m * n)


def critical_m(k: int, n: int, ridge: float, w_bytes: float = 2, a_bytes: float = 2) -> float:
    """Smallest token count m at which the GEMM reaches the ridge point (solves AI(m) = ridge)."""
    denom = 2.0 * k * n - ridge * a_bytes * (k + n)
    if denom <= 0:
        return math.inf  # skinny GEMM: activation traffic alone keeps it memory-bound
    return ridge * w_bytes * k * n / denom


@dataclass(frozen=True)
class Kernel:
    name: str
    flops: float
    bytes: float

    def time(self, gpu: Gpu, dtype: str) -> float:
        return max(self.flops / gpu.peak(dtype), self.bytes / gpu.hbm_bw)

    def bound(self, gpu: Gpu, dtype: str) -> str:
        return "compute" if self.flops / gpu.peak(dtype) >= self.bytes / gpu.hbm_bw else "memory"


def _gemm(name: str, m: int, k: int, n: int, w_bytes: float, a_bytes: float, count: int = 1) -> Kernel:
    return Kernel(name, count * 2.0 * m * k * n,
                  count * (a_bytes * m * k + w_bytes * k * n + a_bytes * m * n))


def layer_gemms(md: DenseModel, tokens: int, tp: int, w_bytes: float, a_bytes: float) -> list[Kernel]:
    """The four GEMMs of one decoder layer on one tensor-parallel rank (Megatron sharding)."""
    q_out = md.n_heads * md.head_dim // tp
    kv_out = 2 * max(1, md.n_kv_heads // tp) * md.head_dim   # KV heads replicate when tp > n_kv
    L = md.n_layers
    return [
        _gemm("qkv_proj", tokens, md.d_model, q_out + kv_out, w_bytes, a_bytes, L),
        _gemm("o_proj", tokens, md.n_heads * md.head_dim // tp, md.d_model, w_bytes, a_bytes, L),
        _gemm("gate_up", tokens, md.d_model, 2 * md.d_ff // tp, w_bytes, a_bytes, L),
        _gemm("down", tokens, md.d_ff // tp, md.d_model, w_bytes, a_bytes, L),
    ]


def allreduce_time(gpu: Gpu, tp: int, nbytes: float) -> float:
    if tp == 1:
        return 0.0
    return gpu.ar_latency + 2.0 * (tp - 1) / tp * nbytes / gpu.ar_busbw


@dataclass(frozen=True)
class StepEstimate:
    kernels: tuple[tuple[str, float, str], ...]   # (name, seconds, bound)
    comm_s: float
    total_s: float
    hbm_bytes: float
    flops: float

    @property
    def intensity(self) -> float:
        return self.flops / self.hbm_bytes


def decode_step(md: DenseModel, gpu: Gpu, tp: int, batch: int, ctx: int,
                w_bytes: float = 2, kv_bytes: float = 2, a_bytes: float = 2,
                dtype: str = "bf16") -> StepEstimate:
    """One decode iteration: `batch` sequences each emit one token while attending to `ctx` tokens."""
    ks = layer_gemms(md, batch, tp, w_bytes, a_bytes)
    ks.append(_gemm("lm_head", batch, md.d_model, md.vocab // tp, w_bytes, a_bytes))
    kv_heads = max(1, md.n_kv_heads // tp)
    q_heads = md.n_heads // tp
    attn_bytes = batch * ctx * 2 * md.n_layers * kv_heads * md.head_dim * kv_bytes
    attn_flops = batch * 4.0 * md.n_layers * q_heads * md.head_dim * ctx
    ks.append(Kernel("attention(kv read)", attn_flops, attn_bytes))
    comm = 2 * md.n_layers * allreduce_time(gpu, tp, batch * md.d_model * a_bytes)
    rows = tuple((k.name, k.time(gpu, dtype), k.bound(gpu, dtype)) for k in ks)
    total = sum(r[1] for r in rows) + comm
    return StepEstimate(rows, comm, total, sum(k.bytes for k in ks), sum(k.flops for k in ks))


def prefill(md: DenseModel, gpu: Gpu, tp: int, prompt: int, mfu: float = 0.5,
            w_bytes: float = 2, a_bytes: float = 2, dtype: str = "bf16") -> StepEstimate:
    """Whole-prompt prefill; attention is causal (half the L^2 score matrix is computed)."""
    ks = layer_gemms(md, prompt, tp, w_bytes, a_bytes)
    ks.append(_gemm("lm_head(last token)", 1, md.d_model, md.vocab // tp, w_bytes, a_bytes))
    q_heads = md.n_heads // tp
    attn_flops = 2.0 * md.n_layers * q_heads * md.head_dim * prompt * prompt
    attn_bytes = 4 * prompt * md.n_layers * q_heads * md.head_dim * a_bytes  # Q,K,V,O once (FlashAttention)
    ks.append(Kernel("attention(causal)", attn_flops, attn_bytes))
    comm = 2 * md.n_layers * allreduce_time(gpu, tp, prompt * md.d_model * a_bytes)
    rows = tuple((k.name, k.time(gpu, dtype) / (mfu if k.bound(gpu, dtype) == "compute" else 1.0),
                  k.bound(gpu, dtype)) for k in ks)
    total = sum(r[1] for r in rows) + comm
    return StepEstimate(rows, comm, total, sum(k.bytes for k in ks), sum(k.flops for k in ks))


def asymptotic_decode_intensity(md: DenseModel, ctx: int, w_bytes: float = 2, kv_bytes: float = 2) -> float:
    """lim_{B->inf} of whole-step FLOP/byte: weight reads amortize away, KV reads do not."""
    per_seq_flops = 2.0 * md.streamed_params + md.attn_flops_per_token(ctx)
    return per_seq_flops / (ctx * md.kv_bytes_per_token(kv_bytes))


def moe_tokens_for_ridge(gpu: Gpu, n_experts: int, top_k: int, w_bytes: float, dtype: str) -> float:
    """Batch tokens needed before an average routed expert's GEMM reaches the ridge point.
    Each expert sees batch*top_k/n_experts tokens; ignoring activation traffic, AI = 2*m/w_bytes."""
    m_needed = gpu.ridge(dtype) * w_bytes / 2.0
    return m_needed * n_experts / top_k


def experts_touched(batch_tokens: int, n_experts: int, top_k: int) -> float:
    """Expected distinct routed experts per MoE layer per step under uniform, independent routing.
    Their weights must ALL be streamed from HBM: 'active parameters' counts FLOPs, not bytes."""
    return n_experts * (1.0 - (1.0 - top_k / n_experts) ** batch_tokens)


def kv_capacity_tokens(md: DenseModel, gpu: Gpu, tp: int, util: float = 0.9,
                       activation_reserve: float = 3 * GiB, w_bytes: float = 2, kv_bytes: float = 2) -> int:
    """Tokens of KV the TP group can hold (vLLM-style: util * HBM - weights - activations)."""
    weights_per_rank = md.total_params * w_bytes / tp
    free = gpu.hbm_bytes * util - weights_per_rank - activation_reserve
    per_token_per_rank = 2 * md.n_layers * max(1, md.n_kv_heads // tp) * md.head_dim * kv_bytes
    return max(0, int(free // per_token_per_rank))


# --------------------------------------------------------------------------- naive vs hardened
def naive_tokens_per_second(md: DenseModel, gpu: Gpu, tp: int) -> float:
    """The napkin formula: HBM bandwidth / model bytes. Ignores batch, KV reads, and comms."""
    return tp * gpu.hbm_bw / (md.total_params * 2)


def max_batch_for_itl(md: DenseModel, gpu: Gpu, tp: int, ctx: int, itl_slo_s: float,
                      util: float = 0.9) -> tuple[int, float]:
    """Largest batch whose estimated inter-token latency meets the SLO AND whose KV fits in HBM."""
    cap = kv_capacity_tokens(md, gpu, tp, util)
    best = (0, 0.0)
    b = 1
    while b * ctx <= cap:
        t = decode_step(md, gpu, tp, b, ctx).total_s
        if t > itl_slo_s:
            break
        best = (b, t)
        b += 1
    return best


# --------------------------------------------------------------------------- self-test / report
def _close(a: float, b: float, rel: float = 1e-3) -> bool:
    return abs(a - b) <= rel * max(abs(a), abs(b))


def main() -> None:
    print("== Ridge points (dense FLOP/s / HBM B/s) ==")
    for g in GPUS:
        fp8 = f"{g.ridge('fp8'):7.1f}" if g.fp8_flops else "    n/a"
        print(f"{g.name:16s} bf16 {g.ridge('bf16'):7.1f}   fp8 {fp8}   FLOP/B")
    assert _close(H100.ridge(), 295.34, 1e-3) and _close(H100.ridge("fp8"), 590.7, 1e-3)

    print("\n== GEMM intensity, K = N = 8192, BF16 ==")
    for m in (1, 8, 64, 256, 318, 512, 2048, 8192):
        print(f"m={m:5d}  AI={gemm_intensity(m, 8192, 8192):8.2f} FLOP/B")
    assert _close(gemm_intensity(1, 8192, 8192), 0.99976, 1e-4)
    assert _close(gemm_intensity(2048, 8192, 8192), 1365.33, 1e-4)
    print(f"critical m on H100 (K=N=8192): {critical_m(8192, 8192, H100.ridge()):.1f} tokens")
    print(f"critical m, TP=8 qkv shard (K=8192,N=1280): {critical_m(8192, 1280, H100.ridge()):.1f} tokens")
    print(f"W4A16 (0.5 B/weight) critical m, K=N=8192: {critical_m(8192, 8192, H100.ridge(), w_bytes=0.5):.1f}")

    md = LLAMA3_70B
    print(f"\n== {md.name} ==  total={md.total_params/1e9:.2f}B  streamed={md.streamed_params/1e9:.2f}B"
          f"  KV/token={md.kv_bytes_per_token():,.0f} B")
    assert md.kv_bytes_per_token() == 327_680
    for L in (4096, 32768):
        print(f"asymptotic decode AI at ctx={L}: {asymptotic_decode_intensity(md, L):.1f} FLOP/B")
    print(f"naive tokens/s/seq on 8xH100 (bandwidth / model bytes): {naive_tokens_per_second(md, H100, 8):.0f}")

    for b, ctx in ((1, 4096), (64, 4096), (256, 4096), (256, 32768)):
        e = decode_step(md, H100, 8, b, ctx)
        print(f"\n-- decode 8xH100 TP=8 batch={b} ctx={ctx}: step={e.total_s*1e3:.2f} ms "
              f"(comm {e.comm_s*1e3:.2f} ms)  AI={e.intensity:.1f}  "
              f"tok/s/user={1/e.total_s:.1f}  tok/s total={b/e.total_s:,.0f}")
        for name, t, bound in e.kernels:
            print(f"   {name:20s} {t*1e3:8.3f} ms  {bound}")

    p = prefill(md, H100, 8, 8192)
    print(f"\n-- prefill 8xH100 TP=8 prompt=8192 @50% MFU: {p.total_s*1e3:.1f} ms "
          f"(comm {p.comm_s*1e3:.1f} ms) AI={p.intensity:.0f}")
    for name, t, bound in p.kernels:
        print(f"   {name:20s} {t*1e3:8.2f} ms  {bound}")

    for L in (32768, 131072):
        p = prefill(md, H100, 8, L)
        attn = next(t for n, t, _ in p.kernels if n.startswith("attention"))
        print(f"prefill prompt={L}: {p.total_s:.2f} s, attention share {attn / p.total_s:.0%}")
    print(f"causal attention FLOPs = GEMM FLOPs at L = "
          f"{md.streamed_params / (md.n_layers * md.n_heads * md.head_dim):,.0f} tokens")

    cap = kv_capacity_tokens(md, H100, 8)
    print(f"\nKV capacity, 8xH100 TP=8, util=0.9, 3 GiB activations: {cap:,} tokens"
          f" -> {cap // 4096} seqs @4K, {cap // 32768} @32K, {cap // 131072} @128K")
    for slo in (0.020, 0.030, 0.050):
        b, t = max_batch_for_itl(md, H100, 8, 4096, slo)
        print(f"max batch @ctx=4096 for ITL<={slo*1e3:.0f} ms: {b} (step {t*1e3:.2f} ms)")

    free = H100.hbm_bytes * 0.9 - md.total_params * 2 / 8 - 3 * GiB
    print(f"vLLM-style blocks (16 tokens, 655,360 B/rank): {int(free // (16 * 40_960)):,}")

    print("\n== TP degree for Llama-3-70B on H100 (ctx 4096) ==")
    for tp in (4, 8):
        c = kv_capacity_tokens(md, H100, tp)
        e = decode_step(md, H100, tp, 64, 4096)
        bmax, tmax = max_batch_for_itl(md, H100, tp, 4096, 0.030)
        tput = bmax / tmax if tmax else 0.0
        print(f"TP={tp}: KV cap {c:>9,} tok ({c // 4096:3d} seqs@4K) | B=64 step {e.total_s*1e3:5.2f} ms"
              f" (comm {e.comm_s*1e3:4.2f}) | ITL<=30ms: B={bmax:3d}, {tput:7,.0f} tok/s"
              f" = {tput / tp:6,.0f} tok/s/GPU")

    print("\n== MoE: batch tokens before an average expert GEMM hits the ridge ==")
    print(f"DeepSeek-V3 (256 routed, top-8), FP8 on H100: "
          f"{moe_tokens_for_ridge(H100, 256, 8, 1.0, 'fp8'):,.0f} tokens per step")
    print(f"Same model, BF16 on H100: {moe_tokens_for_ridge(H100, 256, 8, 2.0, 'bf16'):,.0f} tokens per step")
    for b in (1, 8, 32, 128, 512):
        t = experts_touched(b, 256, 8)
        print(f"batch {b:4d} tokens: {t:6.1f} of 256 routed experts touched per layer ({t / 256:5.1%} of expert bytes)")

    e8 = decode_step(LLAMA3_8B, H100, 1, 1, 1024)
    print(f"\n{LLAMA3_8B.name} 1xH100 batch=1 ctx=1024: {e8.total_s*1e3:.2f} ms/token "
          f"-> {1/e8.total_s:.0f} tok/s ceiling; naive={naive_tokens_per_second(LLAMA3_8B, H100, 1):.0f}")
    print("\nall roofline self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified: CPython 3.14.5, deterministic):

```text
== Ridge points (dense FLOP/s / HBM B/s) ==
A100-SXM4-80GB   bf16   153.0   fp8     n/a   FLOP/B
H100-SXM5-80GB   bf16   295.3   fp8   590.7   FLOP/B
H200-SXM-141GB   bf16   206.1   fp8   412.3   FLOP/B
B200-SXM-180GB   bf16   281.2   fp8   562.5   FLOP/B
L40S-48GB        bf16   419.0   fp8   848.4   FLOP/B

== GEMM intensity, K = N = 8192, BF16 ==
m=    1  AI=    1.00 FLOP/B
m=    8  AI=    7.98 FLOP/B
m=   64  AI=   63.02 FLOP/B
m=  256  AI=  240.94 FLOP/B
m=  318  AI=  295.09 FLOP/B
m=  512  AI=  455.11 FLOP/B
m= 2048  AI= 1365.33 FLOP/B
m= 8192  AI= 2730.67 FLOP/B
critical m on H100 (K=N=8192): 318.3 tokens
critical m, TP=8 qkv shard (K=8192,N=1280): 402.8 tokens
W4A16 (0.5 B/weight) critical m, K=N=8192: 79.6

== Llama-3-70B ==  total=70.55B  streamed=69.50B  KV/token=327,680 B
asymptotic decode AI at ctx=4096: 111.6 FLOP/B
asymptotic decode AI at ctx=32768: 20.9 FLOP/B
naive tokens/s/seq on 8xH100 (bandwidth / model bytes): 190

-- decode 8xH100 TP=8 batch=1 ctx=4096: step=6.85 ms (comm 1.61 ms)  AI=1.1  tok/s/user=145.9  tok/s total=146
   qkv_proj                0.501 ms  memory
   o_proj                  0.401 ms  memory
   gate_up                 2.805 ms  memory
   down                    1.403 ms  memory
   lm_head                 0.078 ms  memory
   attention(kv read)      0.050 ms  memory

-- decode 8xH100 TP=8 batch=64 ctx=4096: step=10.95 ms (comm 2.42 ms)  AI=41.9  tok/s/user=91.3  tok/s total=5,846
   qkv_proj                0.530 ms  memory
   o_proj                  0.429 ms  memory
   gate_up                 2.852 ms  memory
   down                    1.438 ms  memory
   lm_head                 0.079 ms  memory
   attention(kv read)      3.205 ms  memory

-- decode 8xH100 TP=8 batch=256 ctx=4096: step=23.43 ms (comm 4.86 ms)  AI=77.0  tok/s/user=42.7  tok/s total=10,924
   qkv_proj                0.617 ms  memory
   o_proj                  0.513 ms  memory
   gate_up                 2.992 ms  memory
   down                    1.546 ms  memory
   lm_head                 0.082 ms  memory
   attention(kv read)     12.821 ms  memory

-- decode 8xH100 TP=8 batch=256 ctx=32768: step=113.18 ms (comm 4.86 ms)  AI=19.8  tok/s/user=8.8  tok/s total=2,262
   qkv_proj                0.617 ms  memory
   o_proj                  0.513 ms  memory
   gate_up                 2.992 ms  memory
   down                    1.546 ms  memory
   lm_head                 0.082 ms  memory
   attention(kv read)    102.566 ms  memory

-- prefill 8xH100 TP=8 prompt=8192 @50% MFU: 411.7 ms (comm 106.0 ms) AI=1826
   qkv_proj                27.78 ms  compute
   o_proj                  22.23 ms  compute
   gate_up                155.58 ms  compute
   down                    77.79 ms  compute
   lm_head(last token)      0.08 ms  memory
   attention(causal)       22.23 ms  compute
prefill prompt=32768: 1.91 s, attention share 19%
prefill prompt=131072: 11.90 s, attention share 48%
causal attention FLOPs = GEMM FLOPs at L = 106,051 tokens

KV capacity, 8xH100 TP=8, util=0.9, 3 GiB activations: 1,356,942 tokens -> 331 seqs @4K, 41 @32K, 10 @128K
max batch @ctx=4096 for ITL<=20 ms: 203 (step 19.99 ms)
max batch @ctx=4096 for ITL<=30 ms: 331 (step 28.41 ms)
max batch @ctx=4096 for ITL<=50 ms: 331 (step 28.41 ms)
vLLM-style blocks (16 tokens, 655,360 B/rank): 84,808

== TP degree for Llama-3-70B on H100 (ctx 4096) ==
TP=4: KV cap   463,162 tok (113 seqs@4K) | B=64 step 19.26 ms (comm 2.30) | ITL<=30ms: B=113,   4,548 tok/s =  1,137 tok/s/GPU
TP=8: KV cap 1,356,942 tok (331 seqs@4K) | B=64 step 10.95 ms (comm 2.42) | ITL<=30ms: B=331,  11,650 tok/s =  1,456 tok/s/GPU

== MoE: batch tokens before an average expert GEMM hits the ridge ==
DeepSeek-V3 (256 routed, top-8), FP8 on H100: 9,451 tokens per step
Same model, BF16 on H100: 9,451 tokens per step
batch    1 tokens:    8.0 of 256 routed experts touched per layer ( 3.1% of expert bytes)
batch    8 tokens:   57.4 of 256 routed experts touched per layer (22.4% of expert bytes)
batch   32 tokens:  163.3 of 256 routed experts touched per layer (63.8% of expert bytes)
batch  128 tokens:  251.6 of 256 routed experts touched per layer (98.3% of expert bytes)
batch  512 tokens:  256.0 of 256 routed experts touched per layer (100.0% of expert bytes)

Llama-3-8B 1xH100 batch=1 ctx=1024: 4.52 ms/token -> 221 tok/s ceiling; naive=209

all roofline self-checks passed
```

Two results deserve attention:

- **TP=8 beats TP=4 per GPU for Llama-3-70B at 4K context** (1,456 vs 1,137 tok/s/GPU under a 30 ms ITL SLO).
  Two TP=4 replicas store the 141 GB of weights twice, so the 8 GPUs hold only 2 × 463K = 926K tokens of KV instead of
  1.36M. KV capacity is the binding constraint, and less weight replication beats less communication.
- **Llama-3-8B on one H100 models at 221 tok/s, above the napkin's 209.** The napkin divides by *total* parameters, but
  the 0.5B-parameter embedding table is gathered, not streamed. Small corrections like this decide whether an SLO is
  feasible.

### 3.3 The measurement harness (Python + NumPy)

```python
"""cpu_roofline_bench.py - measure the roofline knee on your own CPU (NumPy, ONE thread).

Same physics as a GPU decode step: Y = X @ W^T with the weight W fixed and X = m tokens.
  * "unbatched": m separate GEMVs. Every sequence re-streams all of W (decode without batching).
  * "batched":   one GEMM over m rows. W is streamed once and reused m times (continuous batching).
  * "roofline":  min(peak, AI * BW) using the roofs this script measures.
W is stored [out, in] like torch.nn.Linear. Single-threaded on purpose: ~15 s, laptop-safe.
"""
import os

for var in ("OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "OMP_NUM_THREADS"):
    os.environ.setdefault(var, "1")   # must be set before NumPy loads its BLAS

import time  # noqa: E402

import numpy as np  # noqa: E402

K = N = 4096                          # 64 MiB of FP32 weights: far larger than any L3 cache


def best_of(fn, reps: int = 3) -> float:
    fn()                              # warm-up
    best = float("inf")
    for _ in range(reps):
        t0 = time.perf_counter()
        fn()
        best = min(best, time.perf_counter() - t0)
    return best


def main() -> None:
    w = np.random.default_rng(0).standard_normal((N, K), dtype=np.float32)
    ms = (1, 2, 4, 8, 16, 32, 64, 128, 256, 512)
    rows = []
    for m in ms:
        x = np.random.default_rng(m).standard_normal((m, K), dtype=np.float32)
        flops = 2.0 * m * K * N
        t_batched = best_of(lambda: x @ w.T)
        t_unbatched = best_of(lambda: [w @ x[i] for i in range(m)]) if m <= 64 else float("nan")
        ai = flops / (4.0 * (m * K + K * N + m * N))
        rows.append((m, ai, flops / t_unbatched / 1e9, flops / t_batched / 1e9))

    bw = rows[0][3] / rows[0][1]       # GB/s implied by the m=1 GEMV (a pure bandwidth probe)
    peak = max(r[3] for r in rows)
    print(f"W = {N}x{K} fp32 ({w.nbytes / 2**20:.0f} MiB), 1 thread, best of 3")
    print(f"measured roofs: memory ~{bw:.1f} GB/s, compute ~{peak:.1f} GFLOP/s, ridge ~{peak / bw:.1f} FLOP/B\n")
    print(f"{'m':>4} {'AI FLOP/B':>10} {'unbatched':>10} {'batched':>9} {'roofline':>9}   (GFLOP/s)")
    for m, ai, unb, bat in rows:
        roof = min(peak, ai * bw)
        unb_s = f"{unb:10.1f}" if unb == unb else f"{'-':>10}"
        print(f"{m:4d} {ai:10.2f} {unb_s} {bat:9.1f} {roof:9.1f}")
    assert rows[-1][3] > 4 * rows[0][3], "batched GEMM must beat GEMV per FLOP by a wide margin"
    assert max(r[2] for r in rows if r[2] == r[2]) < 1.5 * rows[0][2], "unbatched GEMVs cannot amortize W"


if __name__ == "__main__":
    main()
```

### 3.4 The hardened way (Java 21): capacity planner and SLO-aware admission controller

The Java gateway in front of the inference fleet (Spring Boot/WebFlux in Folders 06–07) needs the same physics to
decide *whether to admit a request now*. This planner mirrors `roofline.py` exactly; the self-test cross-checks
23.43 ms, 1,356,942 tokens, and batch 203 against the Python output. It contrasts:

- `StaticLimitAdmission`: the naive gateway, a CAS-guarded fixed in-flight limit.
- `RooflineAdmission`: prices each request against **both** physical budgets. KV tokens must fit in HBM, and the
  predicted decode step must meet the ITL SLO with the request included. `outputReserveFraction` trades preemption risk
  (1.0 reserves all of `max_tokens`) against utilization (below 1.0 overcommits, which is safe only because the engine
  can preempt).

It uses `ReentrantLock` rather than `synchronized`, so a virtual thread blocked on the admission lock unmounts from its
carrier on JDK 21–23. JEP 491 removed `synchronized` pinning in JDK 24, but the code targets 21.

```java
// RooflinePlanner.java - Java 21 port of roofline.py, used by a gateway as a capacity planner and an
// SLO-aware admission controller in front of a vLLM/SGLang replica.
// Build & self-test:  javac --release 21 -Xlint:all -Werror -d out RooflinePlanner.java
//                     java -ea -cp out dev.l7.ai.inference.RooflinePlanner
package dev.l7.ai.inference;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.locks.ReentrantLock;

public final class RooflinePlanner {

    private RooflinePlanner() {}

    static final double GIB = 1L << 30;

    public enum Dtype { BF16, FP8 }

    public record Gpu(String name, double bf16Flops, double fp8Flops, double hbmBw, double hbmBytes,
                      double arBusBw, double arLatency) {
        public double peak(Dtype d) {
            double f = d == Dtype.FP8 ? fp8Flops : bf16Flops;
            if (f <= 0) throw new IllegalArgumentException(name + " has no " + d + " tensor cores");
            return f;
        }

        /** FLOP/byte where the HBM roof meets the compute roof. */
        public double ridge(Dtype d) { return peak(d) / hbmBw; }
    }

    public static final Gpu H100 = new Gpu("H100-SXM5-80GB", 989.4e12, 1978.9e12, 3.35e12, 79.1 * GIB, 360e9, 10e-6);

    /** Llama-style decoder: fused QKV, SwiGLU MLP. All products are computed in long. */
    public record DenseModel(String name, int dModel, int nLayers, int nHeads, int nKvHeads, int headDim,
                             int dFf, int vocab, boolean tied) {
        long layerParams() {
            return (long) dModel * headDim * (2L * nHeads + 2L * nKvHeads) + 3L * dModel * dFf;
        }

        /** Weights streamed from HBM every step: all layers + LM head (embedding gather excluded). */
        long streamedParams() { return nLayers * layerParams() + (long) vocab * dModel; }

        long totalParams() { return streamedParams() + (tied ? 0L : (long) vocab * dModel); }

        int kvHeadsPerRank(int tp) { return Math.max(1, nKvHeads / tp); }   // replicate when tp > nKv

        long kvBytesPerTokenPerRank(int tp, int kvBytes) {
            return 2L * nLayers * kvHeadsPerRank(tp) * headDim * kvBytes;
        }
    }

    public static final DenseModel LLAMA3_70B =
            new DenseModel("Llama-3-70B", 8192, 80, 64, 8, 128, 28672, 128256, false);

    record Kernel(String name, double flops, double bytes) {
        double seconds(Gpu g, Dtype d) { return Math.max(flops / g.peak(d), bytes / g.hbmBw()); }
    }

    public record StepEstimate(double totalSeconds, double commSeconds, double attentionSeconds,
                               double hbmBytes, double flops) {
        public double intensity() { return flops / hbmBytes; }
    }

    static double gemmIntensity(long m, long k, long n, double wBytes, double aBytes) {
        return 2.0 * m * k * n / (aBytes * m * k + wBytes * k * n + aBytes * m * n);
    }

    private static Kernel gemm(String name, long m, long k, long n, double wB, double aB, int count) {
        return new Kernel(name, count * 2.0 * m * k * n, count * (aB * m * k + wB * k * n + aB * m * n));
    }

    private static double allReduce(Gpu g, int tp, double bytes) {
        return tp == 1 ? 0.0 : g.arLatency() + 2.0 * (tp - 1) / tp * bytes / g.arBusBw();
    }

    /**
     * One decode iteration for {@code batch} sequences whose cached contexts sum to
     * {@code totalContextTokens}. GEMM cost depends on the batch; attention cost depends only on
     * the total number of cached tokens that must be read from HBM.
     */
    public static StepEstimate decodeStep(DenseModel md, Gpu g, int tp, int batch, long totalContextTokens) {
        final double w = 2, a = 2, kv = 2;
        final Dtype d = Dtype.BF16;
        int qOut = md.nHeads() * md.headDim() / tp;
        int kvOut = 2 * md.kvHeadsPerRank(tp) * md.headDim();
        int layers = md.nLayers();
        List<Kernel> ks = new ArrayList<>(List.of(
                gemm("qkv_proj", batch, md.dModel(), qOut + kvOut, w, a, layers),
                gemm("o_proj", batch, (long) md.nHeads() * md.headDim() / tp, md.dModel(), w, a, layers),
                gemm("gate_up", batch, md.dModel(), 2L * md.dFf() / tp, w, a, layers),
                gemm("down", batch, md.dFf() / tp, md.dModel(), w, a, layers),
                gemm("lm_head", batch, md.dModel(), md.vocab() / tp, w, a, 1)));
        Kernel attn = new Kernel("attention",
                4.0 * layers * (md.nHeads() / tp) * md.headDim() * totalContextTokens,
                (double) totalContextTokens * 2 * layers * md.kvHeadsPerRank(tp) * md.headDim() * kv);
        ks.add(attn);
        double comm = 2.0 * layers * allReduce(g, tp, (double) batch * md.dModel() * a);
        double total = comm;
        double bytes = 0, flops = 0;
        for (Kernel k : ks) {
            total += k.seconds(g, d);
            bytes += k.bytes();
            flops += k.flops();
        }
        return new StepEstimate(total, comm, attn.seconds(g, d), bytes, flops);
    }

    /** Tokens of KV the TP group can hold: util * HBM - weights - activation reserve, per rank. */
    public static long kvCapacityTokens(DenseModel md, Gpu g, int tp, double util, double activationReserve) {
        double free = g.hbmBytes() * util - md.totalParams() * 2.0 / tp - activationReserve;
        return Math.max(0L, (long) Math.floor(free / md.kvBytesPerTokenPerRank(tp, 2)));
    }

    /** Naive napkin math: HBM bandwidth / model bytes. Ignores batch, KV reads, comms. */
    public static double naiveTokensPerSecond(DenseModel md, Gpu g, int tp) {
        return tp * g.hbmBw() / (md.totalParams() * 2.0);
    }

    /** Largest uniform batch at context {@code ctx} that meets the ITL SLO and fits in HBM. */
    public static int maxBatchForItl(DenseModel md, Gpu g, int tp, long ctx, double itlSlo, long capacity) {
        int best = 0;
        for (int b = 1; (long) b * ctx <= capacity; b++) {
            if (decodeStep(md, g, tp, b, b * ctx).totalSeconds() > itlSlo) break;
            best = b;
        }
        return best;
    }

    // ------------------------------------------------------------------ admission control

    /** The naive gateway: a static concurrency limit picked once from a short-context load test. */
    public static final class StaticLimitAdmission {
        private final AtomicInteger inFlight = new AtomicInteger();
        private final int limit;

        public StaticLimitAdmission(int limit) { this.limit = limit; }

        public boolean tryAdmit() {
            while (true) {
                int cur = inFlight.get();
                if (cur >= limit) return false;
                if (inFlight.compareAndSet(cur, cur + 1)) return true;
            }
        }

        public void release() { inFlight.decrementAndGet(); }
    }

    /**
     * The hardened gateway: every admission is priced against two physical budgets, the KV bytes
     * the replica can hold and the decode step time the SLO allows. Output length is unknown, so a
     * configurable fraction of max_tokens is reserved (1.0 = never preempt; less = overcommit).
     */
    public static final class RooflineAdmission {
        private final DenseModel md;
        private final Gpu gpu;
        private final int tp;
        private final double itlSlo;
        private final long kvCapacity;
        private final double outputReserveFraction;
        private final ReentrantLock lock = new ReentrantLock();   // not synchronized: no VT pinning on JDK 21-23
        private int running;
        private long reservedTokens;

        public RooflineAdmission(DenseModel md, Gpu gpu, int tp, double itlSlo, long kvCapacity,
                                 double outputReserveFraction) {
            this.md = md;
            this.gpu = gpu;
            this.tp = tp;
            this.itlSlo = itlSlo;
            this.kvCapacity = kvCapacity;
            this.outputReserveFraction = outputReserveFraction;
        }

        public long reservation(int promptTokens, int maxNewTokens) {
            return promptTokens + (long) Math.ceil(maxNewTokens * outputReserveFraction);
        }

        public boolean tryAdmit(int promptTokens, int maxNewTokens) {
            long r = reservation(promptTokens, maxNewTokens);
            lock.lock();
            try {
                if (reservedTokens + r > kvCapacity) return false;                  // KV budget
                double step = decodeStep(md, gpu, tp, running + 1, reservedTokens + r).totalSeconds();
                if (step > itlSlo) return false;                                    // ITL budget
                running++;
                reservedTokens += r;
                return true;
            } finally {
                lock.unlock();
            }
        }

        public void release(int promptTokens, int maxNewTokens) {
            long r = reservation(promptTokens, maxNewTokens);
            lock.lock();
            try {
                running--;
                reservedTokens -= r;
                if (running < 0 || reservedTokens < 0) throw new IllegalStateException("double release");
            } finally {
                lock.unlock();
            }
        }

        public long reservedTokens() {
            lock.lock();
            try { return reservedTokens; } finally { lock.unlock(); }
        }

        public int running() {
            lock.lock();
            try { return running; } finally { lock.unlock(); }
        }
    }

    // ------------------------------------------------------------------ self-test

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    private static boolean close(double a, double b, double rel) {
        return Math.abs(a - b) <= rel * Math.max(Math.abs(a), Math.abs(b));
    }

    public static void main(String[] args) throws Exception {
        DenseModel md = LLAMA3_70B;
        check(close(H100.ridge(Dtype.BF16), 295.34, 1e-3), "ridge");
        check(close(gemmIntensity(2048, 8192, 8192, 2, 2), 1365.33, 1e-4), "prefill AI");
        check(close(gemmIntensity(1, 8192, 8192, 2, 2), 0.99976, 1e-4), "decode AI");
        // HF reports 70,553,706,496 params; the 161 RMSNorm vectors (80*2 + 1) * 8192 make up the difference.
        check(md.totalParams() + 161L * 8192 == 70_553_706_496L, "param count " + md.totalParams());

        StepEstimate e = decodeStep(md, H100, 8, 256, 256L * 4096);
        System.out.printf("decode TP=8 B=256 ctx=4096: %.2f ms (attention %.2f ms, comm %.2f ms), AI %.1f%n",
                e.totalSeconds() * 1e3, e.attentionSeconds() * 1e3, e.commSeconds() * 1e3, e.intensity());
        check(close(e.totalSeconds(), 23.43e-3, 2e-3), "matches roofline.py (23.43 ms)");

        long cap = kvCapacityTokens(md, H100, 8, 0.9, 3 * GIB);
        System.out.printf("KV capacity: %,d tokens (roofline.py: 1,356,942)%n", cap);
        check(cap == 1_356_942L, "capacity matches roofline.py");
        int b20 = maxBatchForItl(md, H100, 8, 4096, 0.020, cap);
        System.out.printf("max batch @4K for ITL<=20 ms: %d%n", b20);
        check(b20 == 203, "matches roofline.py (203)");
        System.out.printf("naive tokens/s/seq: %.0f vs modeled at B=1: %.0f%n",
                naiveTokensPerSecond(md, H100, 8), 1 / decodeStep(md, H100, 8, 1, 4096).totalSeconds());

        // Naive gateway: limit 256 tuned at 4K context. Traffic shifts to 32K-token RAG prompts.
        StaticLimitAdmission naive = new StaticLimitAdmission(256);
        int admittedNaive = 0;
        while (naive.tryAdmit()) admittedNaive++;
        StepEstimate shifted = decodeStep(md, H100, 8, admittedNaive, admittedNaive * 32_768L);
        long demand = admittedNaive * 32_768L;
        System.out.printf("static limit: admits %d x 32K -> predicted ITL %.1f ms, KV demand %,d tokens = %.1fx capacity%n",
                admittedNaive, shifted.totalSeconds() * 1e3, demand, (double) demand / cap);
        check(demand > cap && shifted.totalSeconds() > 0.05, "naive limit blows both budgets");

        // Hardened gateway, same shift: it prices each request.
        RooflineAdmission hard = new RooflineAdmission(md, H100, 8, 0.050, cap, 1.0);
        int admittedHard = 0;
        while (hard.tryAdmit(31_744, 1_024)) admittedHard++;
        StepEstimate safe = decodeStep(md, H100, 8, admittedHard, hard.reservedTokens());
        System.out.printf("roofline admission: admits %d x 32K -> worst-case ITL %.1f ms, KV %,d / %,d%n",
                admittedHard, safe.totalSeconds() * 1e3, hard.reservedTokens(), cap);
        check(hard.reservedTokens() <= cap && safe.totalSeconds() <= 0.050, "hardened respects budgets");

        // Concurrency: 20,000 virtual threads race admissions with mixed prompt sizes.
        RooflineAdmission shared = new RooflineAdmission(md, H100, 8, 0.030, cap, 0.5);
        AtomicInteger admitted = new AtomicInteger(), rejected = new AtomicInteger(), violations = new AtomicInteger();
        try (ExecutorService vt = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < 20_000; i++) {
                vt.submit(() -> {
                    int prompt = ThreadLocalRandom.current().nextInt(256, 16_384);
                    int maxNew = ThreadLocalRandom.current().nextInt(64, 2_048);
                    if (shared.tryAdmit(prompt, maxNew)) {
                        admitted.incrementAndGet();
                        if (shared.reservedTokens() > cap) violations.incrementAndGet();
                        Thread.yield();
                        shared.release(prompt, maxNew);
                    } else {
                        rejected.incrementAndGet();
                    }
                });
            }
        }
        System.out.printf("virtual-thread race: admitted=%d rejected=%d violations=%d, final running=%d reserved=%d%n",
                admitted.get(), rejected.get(), violations.get(), shared.running(), shared.reservedTokens());
        check(violations.get() == 0 && shared.running() == 0 && shared.reservedTokens() == 0, "no leaks");
        System.out.println("all RooflinePlanner self-checks passed");
    }
}
```

Output (one measured run; the admitted/rejected split in the virtual-thread race varies run to run, the invariants do
not):

```text
decode TP=8 B=256 ctx=4096: 23.43 ms (attention 12.82 ms, comm 4.86 ms), AI 77.0
KV capacity: 1,356,942 tokens (roofline.py: 1,356,942)
max batch @4K for ITL<=20 ms: 203
naive tokens/s/seq: 190 vs modeled at B=1: 146
static limit: admits 256 x 32K -> predicted ITL 113.2 ms, KV demand 8,388,608 tokens = 6.2x capacity
roofline admission: admits 41 x 32K -> worst-case ITL 23.8 ms, KV 1,343,488 / 1,356,942
virtual-thread race: admitted=3809 rejected=16191 violations=0, final running=0 reserved=0
all RooflinePlanner self-checks passed
```

The decisive lines: after the traffic shift, the static limit admits 256 requests of 32K tokens. That is 8.4M tokens of
KV demand against 1.36M of capacity (6.2×), with a predicted ITL of 113 ms. The roofline controller admits 41, keeps
the worst-case ITL at 23.8 ms, and leaves 0.99% of KV headroom.

**Production wiring notes** (built out in Folder 07, file 04):

- Feed `RooflineAdmission` from live engine metrics, not only from its own bookkeeping, and reconcile on every scrape.
  Requests can finish early, abort on client disconnect, or be preempted. Relevant vLLM metrics:
  `vllm:num_requests_running`, `vllm:kv_cache_usage_perc` (⚠ metric names changed across V0/V1; verify).
- Reject with **HTTP 429 + `Retry-After`**, never by queueing unboundedly in the gateway. A queue in front of a
  memory-bound engine converts overload into TTFT explosions.
- Budget per **model × context bucket**. A request with a 120K-token prompt should route to a pool with large KV
  headroom, possibly a different TP degree or FP8 KV (File 02).

---

## 4. Production failure modes and P99 debugging

Each entry gives the **symptom**, the **metric signature**, the **root cause in roofline terms**, the **fix**, and
**prevention**.

### F1 · "We upgraded A100 → H100 and decode only got ~1.6× faster, not 3×"

- **Symptom:** prefill benchmarks improve ~3×, but tokens/s per user in production improves ~1.5–1.6×.
- **Signature:** DCGM `DCGM_FI_PROF_DRAM_ACTIVE` is high (≳ 0.7) during decode while
  `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` is low (≲ 0.2).
- **Root cause:** decode runs on the memory roof, and the bandwidth ratio is 3.35/2.039 = **1.64×**. The 3.2× compute
  ratio applies only to compute-bound kernels (prefill).
- **Fix:** for decode-heavy fleets, buy bandwidth (H200: 4.8 TB/s) or cut bytes (FP8 weights and KV, GQA/MLA models,
  speculative decoding to raise query tokens per weight load).
- **Prevention:** procurement models must split prefill FLOPs from decode bytes. Never compare GPUs on a single
  "TFLOPS" figure.

### F2 · ITL p99 doubles after a product launch, with the same QPS and the same running batch

- **Symptom:** dashboards show unchanged request rate and `num_requests_running`, but ITL p99 jumps from 25 ms to 60+
  ms.
- **Signature:** the sum of context tokens across running sequences rises. vLLM's `kv_cache_usage_perc` climbs, and
  prompt-length histograms shift right (a RAG feature launched with 20–30K-token contexts).
- **Root cause:** the KV term $\kappa \sum L_i / B_{\text{HBM}}$ grows linearly with context. In §1.7, 256 sequences
  go from 23 ms at 4K to 113 ms at 32K.
- **Fix:** admission priced in KV tokens (§3.4), context-length-aware routing to a long-context pool, FP8 KV cache, and
  prompt compression (Folder 04).
- **Prevention:** SLOs and autoscaling must key on **in-flight KV tokens**, not request count.

### F3 · A static concurrency limit causes preemption storms on long prompts

- **Symptom:** throughput falls while GPU utilization looks high. Some requests take 5–10× longer end to end.
- **Signature:** `vllm:num_preemptions_total` slope > 0, KV usage pinned near 100%, recompute prefills interleaved with
  decodes (ITL spikes).
- **Root cause:** a limit tuned at short context admits more KV than HBM holds (6.2× in §3.4). The engine must evict
  running sequences and recompute them (File 03 simulates this).
- **Fix:** KV-priced admission, `outputReserveFraction` around 0.5–1.0 depending on output-length variance, and
  per-tenant max context.
- **Prevention:** load-test with the production prompt-length distribution, including the p99 prompt.

### F4 · INT4 (W4A16) made the model faster at batch 1 and slower at batch 256

- **Symptom:** a quantized deployment wins single-user latency benchmarks and loses throughput at peak.
- **Signature:** at high batch, the GEMMs show high SM/ALU activity (dequantization) and tensor-pipe activity lower
  than the BF16 baseline.
- **Root cause:** W4A16 moves the GEMM knee from ~318 to ~80 tokens. Beyond it the layer is compute-bound, and every
  INT4 weight must be unpacked and converted before the BF16 MMA. That is extra work the BF16 model never does. Marlin
  shows near-ideal ~4× speedups only up to batch sizes in the tens, with gains shrinking beyond (Frantar et al.).
- **Fix:** match quantization to the regime. W4A16 for latency-critical low-batch tiers. W8A8-FP8 (Hopper/Blackwell)
  for high-batch tiers, because it halves bytes *and* doubles the compute roof.
- **Prevention:** benchmark every quantization at batch 1, the SLO batch, and saturation batch, then plot all three on
  the roofline.

### F5 · TP=8 on a model that fits on one GPU

- **Symptom:** an 8B model sharded TP=8 "for speed" delivers worse throughput per GPU than eight TP=1 replicas.
- **Signature:** in Nsight Systems, NCCL kernels occupy a large share of each decode step, and GEMMs are tiny
  (sub-10 µs).
- **Root cause:** sharding divides GEMM bytes by 8, but each all-reduce costs a ~10 µs floor, ×64 per step for 32
  layers. Skinny shards also raise the critical batch (402.8 vs 318.3 tokens above).
- **Fix:** use the smallest TP that fits weights plus the KV headroom the SLO needs, then scale out with data-parallel
  replicas.
- **Prevention:** make TP a capacity-plan output (§3.2 compares TP=4 and TP=8), never a default.

### F6 · "The GPU is only 30% utilized, add more load"

- **Symptom:** `nvidia-smi` shows high GPU-Util while throughput is poor, or low Util while latency is terrible.
- **Signature:** `nvidia-smi`'s GPU-Util is the fraction of time *any kernel* was resident, not SM or tensor-core
  occupancy.
- **Root cause:** a single memory-bound GEMV kernel shows ~100% "Util" while tensor cores idle above 99% of the time.
- **Fix:** use DCGM profiling fields (`DCGM_FI_PROF_SM_ACTIVE`, `..._SM_OCCUPANCY`, `..._PIPE_TENSOR_ACTIVE`,
  `..._DRAM_ACTIVE`). For per-kernel truth, use Nsight Compute's Speed-of-Light and roofline sections
  (`ncu --section SpeedOfLight`).
- **Prevention:** compute MBU and MFU per deployment, not "GPU utilization".

### F7 · MoE capacity plan built on active parameters

- **Symptom:** a 671B-total / 37B-active MoE deployed on hardware sized for a 37B dense model delivers a fraction of
  the planned decode throughput.
- **Signature:** step time scales with the number of *distinct* experts touched, and HBM traffic per step is far above
  37B × bytes.
- **Root cause:** §1.8. At 32 tokens per step, 64% of routed-expert bytes are streamed, and expert GEMMs stay
  memory-bound until ~9.5K tokens per step.
- **Fix:** expert parallelism wide enough to concentrate tokens per expert, large decode batches, and FP8 experts.
  All-to-all costs move to the network (Folder 02).
- **Prevention:** plan MoE with *two* parameter counts: active (FLOPs) and touched (bytes).

### F8 · Long prompts stall every user's stream (preview of Folder 02)

- **Symptom:** sawtooth ITL. Each time a long prompt is admitted, all streaming users see a multi-hundred-millisecond
  pause.
- **Root cause:** an unchunked 8K prefill costs ~400 ms of compute-bound work (§1.5) inside a step that also carries
  memory-bound decodes. Every decode waits.
- **Fix:** chunked prefill (Sarathi). Prefill chunks of a few hundred to a couple thousand tokens ride along with
  decodes, which fills the idle compute roof without blowing the ITL budget. Or disaggregate prefill and decode
  entirely.

---

## 5. FAANG L7 bar-raiser Q&A chains

### Q1 · "Prove that decode is memory-bound. When does batching stop helping?"

- **L5 answer:** "Decode generates one token at a time, so the GPU is underutilized. Batching more requests fixes it."
- **Why L5 fails at scale:** it is qualitative, it implies batching fixes everything, and it misses the KV term
  entirely. That candidate will size a long-context fleet by request count and get paged at 3 a.m. (F2).
- **L7 principal defense:**
  1. The GEMM intensity is $I \approx 2m/b_w$, which in BF16 equals the number of tokens per step. The H100 ridge is
     295, so the linear layers cross it near $m^* \approx 318$ (402 for TP-sharded QKV).
  2. The decode attention kernel has intensity $n_h/n_{kv}$, which is 8 for Llama-3-70B and *independent of batch*. It
     is always memory-bound for GQA.
  3. The whole-step limit is $I_\infty(L) = (2P + 4n_\ell n_h d_h L)/(L\kappa)$: 111.6 at 4K and 20.9 at 32K. Batching
     stops paying when $B L \kappa$ dominates $b_w P$. For Llama-3-70B at 4K that is $B \approx 104$ ($139.0$ GB of
     weights $= B \times 1.342$ GB of KV). Past it, throughput approaches $TP \cdot B_{HBM}/(L\kappa)$ ≈ 20K tok/s at 4K.
  4. Capacity binds first anyway: 331 sequences at 4K on 8×H100, and an ITL SLO of 20 ms binds at 203.
  5. Therefore the levers past that point are **bytes per token** (GQA→MLA, FP8 KV), **query tokens per KV byte**
     (speculative decoding, shared-prefix/cascade attention), and **bandwidth** (H200/B200). More batching is not one
     of them.

### Q2 · "Budget is fixed. Llama-3-70B chat with 4K average context: H100, H200, or L40S?"

- **L5 answer:** "H100. It has the most TFLOPS per dollar for training."
- **Why L5 fails:** chat is decode-dominated, and decode is priced in bytes/s and bytes of capacity. TFLOPS is the
  wrong axis. L40S has no NVLink, so TP=8 over PCIe would make the all-reduce term enormous.
- **L7 defense:**
  1. Decompose the token mix. Chat at 4K context typically sees input:output around 3:1 to 10:1 by token count, but
     decode dominates GPU-seconds because it runs about 300× below the compute roof.
  2. Decode throughput ≈ $\min(\text{BW-bound}, \text{capacity-bound})$. H200 has 1.43× the bandwidth *and* 1.76× the
     capacity. More capacity admits a larger batch, which amortizes weights further. Expect roughly 1.5–1.9× H100's
     decode tokens/s/GPU at long context, and less at short context where weights dominate.
  3. Prefill is compute-bound and identical on H100 and H200. If the workload were summarization (long input, short
     output), H100's price per FLOP would win.
  4. L40S: 0.864 TB/s and 48 GB with no NVLink. It works for small models (≤ 13B, TP=1) or prefill/embedding tiers, and
     is a poor fit for 70B decode.
  5. Answer: an **H200 decode pool**, plus an H100 prefill pool if traffic justifies disaggregation (Folder 02), with
     the split decided by measured TTFT/ITL SLO attainment per dollar.

### Q3 · "Should we quantize Llama-3-70B to 4-bit weights?"

- **L5 answer:** "Yes. 4× smaller means 4× faster, and the quality loss is small."
- **Why L5 fails:** "4× faster" is true only on the memory roof. W4A16 moves the knee to ~80 tokens, and past it
  dequantization is overhead (F4). KV is not quantized by weight-only methods, so at long context the speedup shrinks
  toward 1× because KV bytes dominate (§1.7).
- **L7 defense:**
  1. Split by regime. At batch ≤ ~32, W4A16 is a big win: bytes drop 4× and the kernel stays memory-bound.
  2. At the SLO batch (~200), use FP8 W8A8 on Hopper. It halves bytes and doubles the compute roof, so it wins in both
     regimes.
  3. Separately quantize the KV cache (FP8), because at 32K context KV is 95% of bytes.
  4. Validate quality per task (long-context retrieval is the canary). Plot latency at three batch sizes on the
     roofline before rollout.

### Q4 · "What TP degree would you run Llama-3-70B at, and why not 16?"

- **L5 answer:** "TP=8, because it fits on a node. Higher is faster."
- **Why L5 fails:** the answer is a reflex. It can't explain why TP=8 beats TP=4 per GPU here, or why TP=16 is
  strictly worse.
- **L7 defense:**
  1. From the planner: at TP=4 two replicas per node each store 141 GB of weights, leaving 463K KV tokens per replica
     (926K per node). At TP=8 one replica leaves 1.36M. KV capacity binds, so TP=8 delivers 1,456 vs 1,137 tok/s/GPU at
     a 30 ms ITL.
  2. TP=16 crosses the node boundary. All-reduces then ride InfiniBand/RoCE at roughly a tenth of NVLink bandwidth with
     much higher latency. And since $TP > n_{kv} = 8$, **KV heads are replicated 2×**, so per-rank KV per token stays at
     40,960 B and half the extra HBM is wasted (File 02).
  3. Beyond one node, use pipeline parallelism (cheap point-to-point, bubbles hidden by many microbatches in decode) or
     simply more replicas.
  4. The real answer is "the smallest TP that meets the ITL SLO at the capacity the traffic needs", computed per model
     and context bucket.

### Q5 · "DeepSeek-V3 has 37B active parameters. Why can't we serve it like a 37B dense model?"

- **L5 answer:** "MoE only activates 37B parameters per token, so it costs the same as a 37B model."
- **Why L5 fails:** it confuses FLOPs with bytes. Distinct experts touched per step grow as
  $E(1-(1-k/E)^B)$: 64% of routed-expert bytes at batch 32.
- **L7 defense:**
  1. Memory: all 671B parameters must be resident (roughly 700 GB in FP8 with BF16 embeddings), so this is a multi-GPU, often multi-node,
     deployment no matter what.
  2. Bandwidth: per-step bytes approach the full expert set at modest batch.
  3. Compute: expert GEMMs need about 9,451 tokens per step to reach the ridge.
  4. Hence wide expert parallelism with all-to-all dispatch/combine over NVLink and RDMA (DeepEP), large global decode
     batches, attention run data-parallel to avoid MLA KV replication (File 02), and redundant experts for hot-expert
     load balance.
  5. The cost model is "FLOPs of 37B, bytes of ~671B at low batch, network of an all-to-all".

### Q6 · "ITL p99 spiked when traffic shifted to RAG, but our batch size didn't change. Walk me through it."

- **L5 answer:** "Probably GPU contention or a noisy neighbor. Add replicas."
- **Why L5 fails:** adding replicas without understanding the cause wastes money. The physics predicts this exactly.
- **L7 defense:**
  1. ITL = step time, and step time has a KV term proportional to the total cached tokens across the running batch.
  2. RAG raises per-request context by roughly 5–10×. The model predicts 23 → 113 ms at fixed batch 256 (4K → 32K).
  3. Plus prefill interference: each 30K-token prefill is ~1.5–2 s of compute-bound work. Unchunked, it stalls every
     decode in its step. Chunked, it still steals compute share.
  4. Fixes, in order:
     - KV-token-priced admission.
     - A long-context pool.
     - Chunked prefill with a token budget tuned to the ITL SLO.
     - FP8 KV.
     - Prompt compression and reranking to cut context (Folder 04).
     - Prefix caching for shared retrieved documents (File 03).
  5. Then prove it: plot ITL against $\sum L_i$, which should be nearly linear.

### Q7 · "From first principles, what is the max tokens/s/user for Llama-3-8B on one H100? What makes reality lower?"

- **L5 answer:** "3.35 TB/s ÷ 16 GB ≈ 209 tokens/s."
- **Why L5 fails:** close, but it counts the gathered embedding table as streamed. It also stops at the bound without
  naming the gap to reality, and the gap is the job.
- **L7 defense:**
  1. Streamed bytes ≈ (32 layers + LM head) ≈ 15 GB. The per-kernel model gives 4.52 ms/token at 1K context, about
     221 tok/s.
  2. Reality is lower because of launch overhead (mitigated by CUDA graphs), kernel MBU of roughly 80–90% on skinny
     GEMMs, attention KV reads growing with context (+0.039 µs per cached token per step), sampling and detokenization
     on CPU, and HTTP/SSE framing.
  3. Expect roughly 60–80% of the bound end to end at batch 1, and measure it. MBU per deployment is the KPI.

---

## 6. Invariants checklist

- [ ] Every capacity plan states **context length** (and its distribution), never only request count.
- [ ] Roofline analysis is done **per kernel**. GEMM intensity ≈ tokens per step (BF16). Decode attention intensity =
      $n_h/n_{kv}$, independent of batch.
- [ ] $I_\infty(L) < I^*$ is checked for the target context. If true, the deployment is memory-bound at any batch, and
      levers must reduce bytes or raise bandwidth.
- [ ] KV capacity (tokens) and the ITL SLO **both** gate admission. A static concurrency limit is a bug.
- [ ] TP degree is a computed output: the smallest that fits weights + KV headroom + SLO. Never shard across nodes for
      decode. Never exceed $n_{kv}$ without accounting for KV replication.
- [ ] Quantization choice is validated at batch 1, at the SLO batch, and at saturation.
- [ ] MoE plans carry two parameter counts: active (FLOPs) and touched (bytes).
- [ ] Dashboards report MBU/MFU and DCGM profiling fields, not `nvidia-smi` GPU-Util.
- [ ] Spec-sheet FLOPs are **dense**, and bandwidth and FLOPs are derated by measured efficiency.

## 7. References

1. S. Williams, A. Waterman, D. Patterson. *Roofline: An Insightful Visual Performance Model for Multicore
   Architectures.* CACM 52(4), 2009.
2. J. Kaplan et al. *Scaling Laws for Neural Language Models.* arXiv:2001.08361, 2020 (forward ≈ 2N FLOPs/token).
3. R. Pope et al. *Efficiently Scaling Transformer Inference.* MLSys 2023 (arXiv:2211.05102).
4. G.-I. Yu et al. *Orca: A Distributed Serving System for Transformer-Based Generative Models.* OSDI 2022.
5. W. Kwon et al. *Efficient Memory Management for Large Language Model Serving with PagedAttention.* SOSP 2023.
6. A. Agrawal et al. *Taming Throughput-Latency Tradeoff in LLM Inference with Sarathi-Serve.* OSDI 2024.
7. Y. Zhong et al. *DistServe: Disaggregating Prefill and Decoding for Goodput-optimized LLM Serving.* OSDI 2024.
8. DeepSeek-AI. *DeepSeek-V3 Technical Report.* arXiv:2412.19437, 2024; and *DeepSeek-V3/R1 Inference System
   Overview* (open-infra release, 2025) ⚠ verify deployment figures.
9. E. Frantar et al. *MARLIN: Mixed-Precision Auto-Regressive Parallel Inference on Large Language Models.*
   arXiv:2408.11743, 2024.
10. NVIDIA. *H100 Tensor Core GPU Architecture* whitepaper; H100/H200/B200/L40S datasheets (dense vs sparse figures).
11. Databricks. *LLM Inference Performance Engineering: Best Practices* (2023): MBU/MFU definitions.
12. NVIDIA DCGM documentation: profiling metric fields (`DCGM_FI_PROF_*`); Nsight Compute roofline sections.
