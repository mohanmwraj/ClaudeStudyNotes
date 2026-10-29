# 07.2 · Parameter-Efficient Fine-Tuning: LoRA, QLoRA, Quantization & FlashAttention in PyTorch

> **Folder 07 · Distributed Training, Fine-Tuning & Production ML Systems**
> **Measured on:** PyTorch 2.14.1+cu130 on an NVIDIA GeForce RTX 3050 Laptop GPU (sm_86, 4 GB), i5-11260H, Windows 11. LoRA, NF4 and the online-softmax attention are implemented from scratch in each listing (no `peft`/`bitsandbytes`); int4 GEMV uses PyTorch's built-in tinygemm kernel (`torch._weight_int4pack_mm`), and attention uses `F.scaled_dot_product_attention`'s backends.
> **Design sources:** LoRA (Hu et al. 2021), QLoRA (Dettmers et al. 2023, NF4 values and double quantization), LLM.int8() (Dettmers et al. 2022, outliers), FlashAttention 1/2 (Dao et al. 2022/2023).

---

## 0. Orientation & the JVM/C++ Bridge

Fine-tuning a large model is expensive for three reasons: **trainable state** (optimizer moments for every parameter), **weight bytes** (memory capacity and, at inference, memory bandwidth), and **attention's N² intermediate**. LoRA cuts the first by training a low-rank delta over frozen weights. Quantization cuts the second by storing weights in 4–8 bits with per-block scales. FlashAttention cuts the third by never materializing the score matrix. None of the three changes what the model computes much, but each depends on getting a specific numerical or memory-layout detail right.

| Technique | JVM / data-systems analogue | C/C++ analogue |
|---|---|---|
| LoRA delta over frozen base | an LSM memtable over immutable SSTables; merge = compaction | copy-on-write overlay |
| merge `W + (α/r)BA` | compacting a delta log into the base file | applying a patch |
| blockwise absmax quantization | Parquet/ORC per-page min/max + frame-of-reference encoding | fixed-point with block exponent (block floating point) |
| NF4 code book | dictionary encoding with 16 entries chosen by data distribution | a 16-entry lookup table |
| online softmax (FlashAttention) | an incremental windowed aggregate (Flink `AggregateFunction`) instead of buffering the whole window | Welford / streaming log-sum-exp |
| SDPA backend fallback | a query planner silently choosing a full scan | an `#ifdef` fallback path |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 LoRA

```text
 frozen W ∈ R^{d×k};  trainable A ∈ R^{r×k} (random), B ∈ R^{d×r} (ZERO, so training starts at the base model)
 forward:  y = x Wᵀ + (α/r) · (x Aᵀ) Bᵀ          two thin matmuls; the delta is never materialized as d×k
 trainable parameters per layer: r(d + k) instead of d·k → 1024×1024, r = 8: 16,384 vs 1,048,576 (1.56 %)
 AdamW state ∝ trainable (8 B/param fp32): 0.50 MiB vs 32 MiB for the 4-layer model (measured)
 activations: backward still flows through every frozen W to reach earlier adapters, and A needs its input x,
              so activation memory shrinks less than parameter memory (peak extra 75 → 12.8 MiB here)
 inference: merge W' = W + (α/r) B A once → a plain dense layer, zero added latency (max diff 6.6e-7 measured)
 α/r scaling: keeps the update's magnitude stable when you change r, so the LR doesn't need retuning per rank
```

### 1.2 Quantization: granularity, outliers, NF4

```text
 symmetric absmax: s = max|w| / (2^(b-1) - 1);  q = round(w / s);  ŵ = q · s
 granularity and its storage cost (fp16 scale = 16 bits):
   per tensor           1 scale               8.000 bits/param (int8)
   per channel (row)    1 scale per row        8.004
   per group of 128     1 scale per 128        4 + 16/128 = 4.125 (int4)
 an outlier sets the scale for everything that shares it:
   64 weights of 8.0 in a 4096×4096 matrix of ~N(0, 1/64²): per-tensor int8 lost 93 % of the ordinary weights'
   precision (most round to 0); per-row confined the damage to 64 rows (11.7 %); groups barely noticed (measured)
 NF4 (QLoRA): 16 levels at quantiles of N(0, 1), rescaled to [-1, 1], with an exact 0. Optimal-ish for normally
   distributed weights. Blocks of 64 with an fp32 absmax: 4 + 32/64 = 4.5 bits/param
 double quantization: quantize the absmax values themselves to int8 (groups of 256, one fp32 scale + mean):
   4 + 8/64 + 32/(64·256) = 4.127 bits/param (the QLoRA paper's figure; measured 4.127 by the listing)
```

### 1.3 When quantization makes inference faster

```text
 decode (batch 1): y = x Wᵀ is a GEMV: 2 FLOPs per weight, each weight read once → bandwidth-bound
   time ≈ weight bytes / memory bandwidth → 4-bit weights can be ~4x faster than fp16 IF dequantization happens in
   registers inside the GEMV kernel (fused); dequantizing to an fp16 copy first moves MORE bytes than fp16 alone
 prefill / large batch: GEMM is compute-bound → weight-only quantization saves memory but not time;
   speed needs low-precision tensor-core math on both operands (W8A8 int8, FP8 on Hopper/Ada)
```

Measured for a 4096×4096 layer at batch 1: fp16 **~202 µs** (~166 GB/s). The fused int4 tinygemm kernel took **~82 µs (2.5× faster)**. Naive "dequantize then GEMV" took ~1.15 ms (**5.7× slower**), and `torch.compile` of the same code ~513 µs (2.5× slower). An int8 × int8 GEMM (`torch._int_mm`) at 4096³ ran at **0.7–0.9×** fp16 here, not the 2× an Ampere datasheet suggests. Low-precision speedups are a property of a specific kernel, not of the dtype.

### 1.4 QLoRA

```text
 frozen base: NF4 + double-quantized absmax (4.127 bits/param)  → 16 MiB fp32 → 2.06 MiB for the listing's model
 each forward: dequantize a layer's weight to bf16 just in time, matmul, discard (compute dtype bf16)
 trainable: LoRA A, B in bf16 (+ fp32 optimizer state); paged optimizers (unified memory) for spikes ⚠ not run
 cost: dequantization every forward (step 4.6 ms vs 3.0 ms for LoRA on a dense base, measured)
 quality: NF4's error is full-rank noise (relative weight error 9.2 % here) that a rank-8 adapter can't cancel:
          final loss 1.5e-3 vs 1.0–1.5e-5 for LoRA on the fp32 base, still 48x better than the base model
```

On real LLMs the QLoRA paper found NF4 + LoRA matched 16-bit fine-tuning on benchmarks. The listing's synthetic task, whose target is exactly low-rank, makes the quantization noise floor visible, which real tasks usually hide below their own noise.

### 1.5 Attention memory and FlashAttention

```text
 per head: S = Q Kᵀ/√d (N×N), P = softmax(S), O = P V       FLOPs = 4·N²·d either way
 naive: S and P live in HBM: 2 × N² × 2 bytes per head in fp16; peak grows as N² (measured 41 MiB at N=1024 →
        2056 MiB at N=8192 for 8 heads)
 online softmax (exact): process K/V in blocks j, keep per query row a running max m, denominator l, output o:
     m' = max(m, rowmax(S_j));  l = l·e^(m-m') + rowsum(e^(S_j - m'));  o = o·e^(m-m') + e^(S_j - m') V_j;  O = o / l
 FlashAttention: a block of Q rows in SRAM, stream K/V blocks through it, never write S or P to HBM;
   backward recomputes S from Q, K and the saved (m, l) instead of storing P → O(N) extra memory
   HBM traffic per head: naive ≈ 4·N²·2 bytes for S/P; tiled ≈ Q, O once + K, V once per Q block
   (N=4096, d=64: 128 MiB vs 33 MiB with 128-row blocks). Paper bound: Θ(N² d² / M) for SRAM size M
 FA2: better work partitioning (over sequence, fewer non-matmul FLOPs); FA3: Hopper async + FP8 (⚠ not on Ampere)
```

`F.scaled_dot_product_attention` picks among backends: `FLASH_ATTENTION` (FlashAttention-2 kernels), `EFFICIENT_ATTENTION` (memory-efficient, CUTLASS-based), `CUDNN_ATTENTION` and `MATH` (the reference, which materializes S). ⚠ On this Windows wheel the FLASH backend has **no kernel** ("No available kernel"), but EFFICIENT and CUDNN exist and are tiled. Measured at N = 4096 causal fp16: EFFICIENT ~1.9 ms and CUDNN ~1.75 ms with **4 MiB** extra memory, against MATH at ~51 ms and **1,248 MiB**.

### 1.6 The KV cache (where 07.3 starts)

```text
 KV bytes = 2 (K and V) × layers × kv_heads × head_dim × tokens × batch × bytes_per_value
 a 7B-class model (32 layers, 32 KV heads, head_dim 128, fp16): 2·32·32·128·2 = 512 KiB per token
   → 4,096-token context = 2 GiB per sequence; batch 16 = 32 GiB, more than the weights (13.5 GB)
 levers: grouped-query attention (8 KV heads → 4x less), int8/fp8 KV cache, paged allocation (vLLM PagedAttention)
```

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 LoRA and QLoRA from scratch

```python
"""lora_qlora_from_scratch.py - LoRA and the QLoRA recipe built from first principles on the GPU.

A frozen "pretrained" 4-layer MLP (width 1024) must learn a target that differs from it by a rank-4 update per layer.
A: full fine-tuning vs LoRA (r=8): trainable parameters, optimizer state, peak memory, step time, final loss.
B: merging: W' = W + (alpha/r) B A gives the same outputs with zero inference overhead.
C: QLoRA: the frozen base stored as NF4 (4-bit NormalFloat, blocks of 64, absmax per block, double-quantized absmax),
   dequantized on the fly in forward; LoRA adapters trained on top in bf16. Bits per parameter and final loss.
"""
import time

import torch

dev = torch.device("cuda")
D, LAYERS, RANK = 1024, 4, 8


def base_weights(seed):
    g = torch.Generator(device=dev).manual_seed(seed)
    return [torch.randn(D, D, device=dev, generator=g) / D**0.5 for _ in range(LAYERS)]


W0 = base_weights(0)
g = torch.Generator(device=dev).manual_seed(1)
deltas = [(torch.randn(D, 4, device=dev, generator=g) @ torch.randn(4, D, device=dev, generator=g)) * 0.05 / D**0.5
          for _ in range(LAYERS)]                        # the "task": a rank-4 change per layer
W_target = [w + d for w, d in zip(W0, deltas)]


def mlp(x, weights):
    for i, w in enumerate(weights):
        x = x @ w.T
        if i < LAYERS - 1:
            x = torch.nn.functional.gelu(x)
    return x


class LoRALinear(torch.nn.Module):
    def __init__(self, w, r=RANK, alpha=16, base=None):
        super().__init__()
        self.base = base                                 # callable producing the frozen weight (dense or NF4)
        self.register_buffer("w", w if base is None else None)
        self.A = torch.nn.Parameter(torch.randn(r, w.shape[1], device=dev) / w.shape[1]**0.5)
        self.B = torch.nn.Parameter(torch.zeros(w.shape[0], r, device=dev))   # B = 0: training starts at the base model
        self.scale = alpha / r

    def weight(self):
        return self.w if self.base is None else self.base()

    def forward(self, x):
        return x @ self.weight().T + (x @ self.A.T) @ self.B.T * self.scale

    def merged(self):
        return self.weight() + self.scale * self.B @ self.A


def train(params, forward, steps=300, lr=1e-3, autocast=None):
    opt = torch.optim.AdamW(params, lr=lr)
    gen = torch.Generator(device=dev).manual_seed(2)
    torch.cuda.synchronize()
    torch.cuda.reset_peak_memory_stats()
    base_mem = torch.cuda.memory_allocated()
    t0 = time.perf_counter()
    for _ in range(steps):
        xb = torch.randn(256, D, device=dev, generator=gen)
        with torch.no_grad():
            yb = mlp(xb, W_target)
        with torch.autocast("cuda", dtype=torch.bfloat16, enabled=autocast is not None):
            loss = torch.nn.functional.mse_loss(forward(xb).float(), yb)
        opt.zero_grad(set_to_none=True)
        loss.backward()
        opt.step()
    torch.cuda.synchronize()
    state = sum(v.numel() * v.element_size() for s in opt.state.values() for v in s.values() if torch.is_tensor(v))
    return (time.perf_counter() - t0) / steps * 1e3, loss.item(), state, (torch.cuda.max_memory_allocated() - base_mem) / 2**20


print("== A. full fine-tuning vs LoRA (r=8, alpha=16) on 4 x (1024 x 1024) layers, 300 AdamW steps, batch 256")
full =[torch.nn.Parameter(w.clone()) for w in W0]
ms_f, loss_f, st_f, pk_f = train(full, lambda x: mlp(x, full))
layers = [LoRALinear(w.clone()) for w in W0]
lora_params = [p for layer in layers for p in (layer.A, layer.B)]


def lora_forward(x):
    for i, layer in enumerate(layers):
        x = layer(x)
        if i < LAYERS - 1:
            x = torch.nn.functional.gelu(x)
    return x


with torch.no_grad():
    zero_shot = torch.nn.functional.mse_loss(lora_forward(torch.randn(256, D, device=dev)),
                                             mlp(torch.randn(256, D, device=dev), W_target))
ms_l, loss_l, st_l, pk_l = train(lora_params, lora_forward)
n_full, n_lora = sum(p.numel() for p in full), sum(p.numel() for p in lora_params)
print(f"  {'':22} {'trainable':>11} {'AdamW state':>12} {'peak extra':>11} {'step':>8} {'final loss':>11}")
print(f"  {'full fine-tune':22} {n_full:11,d} {st_f / 2**20:9.1f} MiB {pk_f:8.1f} MiB {ms_f:6.2f}ms {loss_f:11.2e}")
print(f"  {'LoRA r=8':22} {n_lora:11,d} {st_l / 2**20:9.2f} MiB {pk_l:8.1f} MiB {ms_l:6.2f}ms {loss_l:11.2e}")
print(f"  LoRA trains {n_lora / n_full * 100:.2f}% of the parameters; loss at step 0 (base model) {zero_shot.item():.2e}")
assert loss_l < zero_shot.item() / 20 and n_lora < n_full / 50

print("== B. merge for inference")
x = torch.randn(64, D, device=dev)
with torch.no_grad():
    merged = [layer.merged() for layer in layers]
    diff = (mlp(x, merged) - lora_forward(x)).abs().max().item()
print(f"  max |merged - adapter| = {diff:.1e}: same function, plain dense layers, no adapter cost at serving time")
assert diff < 1e-4

print("== C. QLoRA: NF4 base weights + bf16 LoRA adapters")
# NF4 code book: 16 quantiles of N(0, 1) normalized to [-1, 1], with an exact zero (QLoRA, Dettmers et al. 2023)
NF4 = torch.tensor([-1.0, -0.6961928009986877, -0.5250730514526367, -0.39491748809814453, -0.28444138169288635,
                    -0.18477343022823334, -0.09105003625154495, 0.0, 0.07958029955625534, 0.16093020141124725,
                    0.24611230194568634, 0.33791524171829224, 0.44070982933044434, 0.5626170039176941,
                    0.7229568362236023, 1.0], device=dev)


def nf4_quantize(w, block=64, block2=256):
    flat = w.reshape(-1, block)
    absmax = flat.abs().amax(dim=1, keepdim=True)
    idx = (flat / absmax).unsqueeze(-1).sub(NF4).abs().argmin(-1).to(torch.uint8)
    packed = (idx[:, 0::2] << 4) | idx[:, 1::2]          # two 4-bit codes per byte
    am = absmax.reshape(-1, block2)                      # double quantization: absmax -> int8 per group of 256 blocks
    mean = am.mean()
    s2 = (am - mean).abs().amax(dim=1, keepdim=True) / 127
    am_q = torch.round((am - mean) / s2).to(torch.int8)
    return {"packed": packed, "am_q": am_q, "s2": s2, "mean": mean, "shape": w.shape, "block": block}


def nf4_dequantize(q, dtype=torch.bfloat16):
    hi, lo = (q["packed"] >> 4).long(), (q["packed"] & 0xF).long()
    idx = torch.stack((hi, lo), dim=-1).reshape(q["packed"].shape[0], -1)
    absmax = (q["am_q"].float() * q["s2"] + q["mean"]).reshape(-1, 1)
    return (NF4[idx] * absmax).reshape(q["shape"]).to(dtype)


qs = [nf4_quantize(w) for w in W0]
q_bytes = sum(q["packed"].numel() + q["am_q"].numel() + q["s2"].numel() * 4 + 4 for q in qs)
err = sum(((nf4_dequantize(q, torch.float32) - w).norm() / w.norm()).item() for q, w in zip(qs, W0)) / LAYERS
print(f"  storage: fp32 {4 * D * D * LAYERS / 2**20:.0f} MiB, bf16 {2 * D * D * LAYERS / 2**20:.0f} MiB, NF4 + double-quantized "
      f"absmax {q_bytes / 2**20:.2f} MiB = {q_bytes * 8 / (D * D * LAYERS):.3f} bits/param; relative weight error {err:.3f}")
qlayers = [LoRALinear(w, base=(lambda q=q: nf4_dequantize(q))) for w, q in zip(W0, qs)]
for ql in qlayers:
    ql.A.data, ql.B.data = ql.A.data.bfloat16(), ql.B.data.bfloat16()


def qlora_forward(x):
    x = x.bfloat16()
    for i, layer in enumerate(qlayers):
        x = layer(x)
        if i < LAYERS - 1:
            x = torch.nn.functional.gelu(x)
    return x


ms_q, loss_q, st_q, pk_q = train([p for ql in qlayers for p in (ql.A, ql.B)], qlora_forward, lr=1e-3, autocast=True)
print(f"  QLoRA (NF4 base, bf16 adapters): step {ms_q:.2f} ms (dequantize every forward), final loss {loss_q:.2e} "
      f"vs LoRA on the fp32 base {loss_l:.2e}; base-model step-0 loss {zero_shot.item():.2e}")
assert loss_q < zero_shot.item() / 2
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. full fine-tuning vs LoRA (r=8, alpha=16) on 4 x (1024 x 1024) layers, 300 AdamW steps, batch 256
                           trainable  AdamW state  peak extra     step  final loss
  full fine-tune           4,194,304      32.0 MiB     75.1 MiB   5.57ms    6.97e-04
  LoRA r=8                    65,536      0.50 MiB     12.8 MiB   3.09ms    1.33e-05
  LoRA trains 1.56% of the parameters; loss at step 0 (base model) 7.23e-02
== B. merge for inference
  max |merged - adapter| = 6.7e-07: same function, plain dense layers, no adapter cost at serving time
== C. QLoRA: NF4 base weights + bf16 LoRA adapters
  storage: fp32 16 MiB, bf16 8 MiB, NF4 + double-quantized absmax 2.06 MiB = 4.127 bits/param; relative weight error 0.092
  QLoRA (NF4 base, bf16 adapters): step 4.61 ms (dequantize every forward), final loss 1.49e-03 vs LoRA on the fp32 base 1.33e-05; base-model step-0 loss 7.23e-02
ALL ASSERTIONS PASSED
```

* LoRA trained **1.56 %** of the parameters with 64× less optimizer state, ran each step ~1.8× faster, and reached a lower loss than full fine-tuning on this exactly-low-rank target. Full fine-tuning at the same LR is noisier in 4M dimensions.
* Merging is exact to 6.6e-7. Serving pays nothing for having trained with adapters.
* QLoRA stored the base in **2.06 MiB instead of 16 MiB (4.127 bits/param)**, and paid for it with a dequantization per forward and a quantization-noise floor (§1.4).

### 2.2 Quantization: accuracy by granularity, speed by kernel

```python
"""quantization_error_speed.py - what quantization costs in accuracy and buys in bytes and speed.

A: one 4096 x 4096 weight matrix quantized four ways (int8 per-tensor / per-channel, int4 per-group, NF4): bits per
   parameter and output error; then the error on the ordinary weights once 64 outliers share their scale.
B: why weight-only quantization helps decode: batch-1 GEMV is memory-bound, so bytes moved set the time,
   but only if dequantization is fused into the GEMV kernel (PyTorch's int4 tinygemm kernel vs naive dequant).
C: int8 tensor cores: torch._int_mm (int8 x int8 -> int32) vs fp16 matmul throughput at a large batch (measured;
   the 2x peak ratio of the datasheet is not a given).
"""
import torch

dev = torch.device("cuda")
torch.manual_seed(0)
N = 4096
W = torch.randn(N, N, device=dev) / N**0.5
X = torch.randn(64, N, device=dev)


def q_absmax(w, bits, axis=None, group=None):
    qmax = 2 ** (bits - 1) - 1
    if group:
        g = w.reshape(-1, group)
        s = g.abs().amax(dim=1, keepdim=True) / qmax
        return (torch.round(g / s).clamp(-qmax, qmax) * s).reshape(w.shape), bits + 16 / group
    s = (w.abs().amax() if axis is None else w.abs().amax(dim=axis, keepdim=True)) / qmax
    extra = 0 if axis is None else 16 * w.shape[0] / w.numel()
    return torch.round(w / s).clamp(-qmax, qmax) * s, bits + extra


NF4 = torch.tensor([-1.0, -0.6962, -0.5251, -0.3949, -0.2844, -0.1848, -0.0911, 0.0, 0.0796, 0.1609, 0.2461, 0.3379,
                    0.4407, 0.5626, 0.7230, 1.0], device=dev)


def q_nf4(w, block=64):
    b = w.reshape(-1, block)
    s = b.abs().amax(dim=1, keepdim=True)
    idx = (b / s).unsqueeze(-1).sub(NF4).abs().argmin(-1)
    return (NF4[idx] * s).reshape(w.shape), 4 + 32 / block


schemes = [("int8 per-tensor absmax", lambda w: q_absmax(w, 8)),
           ("int8 per-channel (row) absmax", lambda w: q_absmax(w, 8, axis=1)),
           ("int4 per-group of 128 absmax", lambda w: q_absmax(w, 4, group=128)),
           ("NF4 per-block of 64 (QLoRA)", q_nf4)]
print("== A. output error ||X W^T - X Q(W)^T|| / ||X W^T||, and weight error on non-outliers")
W_out = W.clone()
pos = torch.randperm(N * N, device=dev)[:64]
W_out.view(-1)[pos] = 8.0                                # 64 outliers of ~500 sigma in random rows
normal = torch.ones(N * N, dtype=torch.bool, device=dev)
normal[pos] = False
ref = X @ W.T
print(f"  {'scheme':32} {'bits/param':>10} {'output error':>13} {'normal-weight error, 64 outliers':>34}")
errs = {}
for label, fn in schemes:
    qw, bits = fn(W)
    qo, _ = fn(W_out)
    e = ((X @ qw.T - ref).norm() / ref.norm()).item()
    eo = ((qo.view(-1)[normal] - W_out.view(-1)[normal]).norm() / W_out.view(-1)[normal].norm()).item()
    errs[label] = (e, eo)
    print(f"  {label:32} {bits:10.3f} {e:13.4f} {eo:34.4f}")
assert errs["int8 per-tensor absmax"][1] > 5 * errs["int8 per-channel (row) absmax"][1]
assert errs["int4 per-group of 128 absmax"][1] < errs["int8 per-tensor absmax"][1]


def gpu_ms(fn, reps=50):
    fn()
    torch.cuda.synchronize()
    a, b = torch.cuda.Event(enable_timing=True), torch.cuda.Event(enable_timing=True)
    a.record()
    for _ in range(reps):
        fn()
    b.record()
    torch.cuda.synchronize()
    return a.elapsed_time(b) / reps


print("== B. decode-style GEMV (batch 1): bytes moved decide the time")
x1 = torch.randn(1, N, device=dev, dtype=torch.float16)
w16 = W.half()
w8 = torch.round(W / (W.abs().amax(dim=1, keepdim=True) / 127)).to(torch.int8)
s8 = (W.abs().amax(dim=1, keepdim=True) / 127).half()
t16 = gpu_ms(lambda: x1 @ w16.T)
t8_naive = gpu_ms(lambda: x1 @ (w8.half() * s8).T)          # dequantize the whole matrix, then GEMV
t8_comp = gpu_ms(torch.compile(lambda: (x1 * 1.0) @ (w8.half() * s8).T))
gs = 128                                                 # int4 per-group (asymmetric codes 0..15, zero point 8)
wg = W.reshape(N, N // gs, gs)
sc = wg.abs().amax(-1, keepdim=True) / 7
q4 = (torch.round(wg / sc) + 8).clamp(0, 15).to(torch.int32).reshape(N, N)
w4 = torch._convert_weight_to_int4pack((q4[:, ::2] << 4 | q4[:, 1::2]).to(torch.uint8), 8)
sz = torch.stack([sc.reshape(N, N // gs).T, torch.zeros(N // gs, N, device=dev)], dim=-1).bfloat16().contiguous()
x1b = x1.bfloat16()
ref4 = x1b.float() @ (((q4 - 8).float().reshape(N, N // gs, gs) * sc).reshape(N, N)).T
assert ((torch._weight_int4pack_mm(x1b, w4, gs, sz).float() - ref4).norm() / ref4.norm()).item() < 0.01
t4 = gpu_ms(lambda: torch._weight_int4pack_mm(x1b, w4, gs, sz))
for label, t, nbytes in (("fp16 weights (32 MiB read)", t16, 2 * N * N),
                         ("int8 weights, eager dequant + GEMV", t8_naive, N * N + 2 * N * N * 2),
                         ("int8 weights, torch.compile", t8_comp, N * N),
                         ("int4 weights, fused tinygemm kernel", t4, N * N // 2 + sz.numel() * 2)):
    print(f"  {label:38} {t * 1e3:7.1f} us   ~{nbytes / 2**20:4.0f} MiB of traffic   {nbytes / (t / 1e3) / 1e9:5.0f} GB/s")

print("== C. int8 tensor cores: torch._int_mm vs fp16 matmul, 4096 x 4096 x 4096")
a8 = torch.randint(-127, 127, (N, N), device=dev, dtype=torch.int8)
b8 = torch.randint(-127, 127, (N, N), device=dev, dtype=torch.int8)
a16, b16 = a8.half(), b8.half()
assert torch.equal(torch._int_mm(a8[:64], b8[:, :64]).cpu(), a8[:64].cpu().int() @ b8[:, :64].cpu().int())
t_i8, t_f16 = gpu_ms(lambda: torch._int_mm(a8, b8), reps=10), gpu_ms(lambda: a16 @ b16, reps=10)
ops = 2 * N**3
print(f"  fp16 matmul        {t_f16:6.2f} ms  {ops / t_f16 / 1e9:5.1f} TFLOP/s")
print(f"  int8 _int_mm       {t_i8:6.2f} ms  {ops / t_i8 / 1e9:5.1f} TOP/s   ({t_f16 / t_i8:.1f}x)")
assert t4 < t16                                          # int8 GEMM speed is measured, not assumed (see text)
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. output error ||X W^T - X Q(W)^T|| / ||X W^T||, and weight error on non-outliers
  scheme                           bits/param  output error   normal-weight error, 64 outliers
  int8 per-tensor absmax                8.000        0.0122                             0.9319
  int8 per-channel (row) absmax         8.004        0.0087                             0.1167
  int4 per-group of 128 absmax          4.125        0.1171                             0.1193
  NF4 per-block of 64 (QLoRA)           4.500        0.0918                             0.0933
== B. decode-style GEMV (batch 1): bytes moved decide the time
  fp16 weights (32 MiB read)               202.0 us   ~  32 MiB of traffic     166 GB/s
  int8 weights, eager dequant + GEMV      1166.9 us   ~  80 MiB of traffic      72 GB/s
  int8 weights, torch.compile              512.6 us   ~  16 MiB of traffic      33 GB/s
  int4 weights, fused tinygemm kernel       81.9 us   ~   8 MiB of traffic     109 GB/s
== C. int8 tensor cores: torch._int_mm vs fp16 matmul, 4096 x 4096 x 4096
  fp16 matmul         11.60 ms   11.9 TFLOP/s
  int8 _int_mm        14.93 ms    9.2 TOP/s   (0.8x)
ALL ASSERTIONS PASSED
```

* **A**: per-channel int8 is nearly free (output error 0.9 %). Per-tensor is fine on clean weights (1.2 %) but **collapses with outliers** (93 % error on the ordinary weights). NF4 beat uniform int4 (9.2 % vs 11.7 % output error), though at 4.5 vs 4.125 bits; double quantization (§1.2) closes most of that storage gap.
* **B**: the slow trap is "dequantize then multiply" (5.7× *slower* than fp16). The pattern is a fused weight-only kernel (int4 tinygemm: 2.5× faster than fp16, at ~109 GB/s effective).
* **C**: int8 tensor-core GEMM through `torch._int_mm` didn't beat fp16 on this GPU (0.7–0.9×). Measure the kernel you'll ship.

### 2.3 Attention without the N² matrix

```python
"""flash_attention_tiling.py - why FlashAttention works: the N x N score matrix never has to exist.

A: naive attention materializes S = QK^T and P = softmax(S): peak memory and time grow as N^2.
B: the online-softmax recurrence, written in plain PyTorch over key blocks, equals exact attention with O(N x block)
   extra memory (the algorithm FlashAttention runs inside SRAM).
C: torch's scaled_dot_product_attention backends on this GPU/build: which exist, their time and peak memory.
D: the arithmetic: FLOPs are identical; what changes is HBM traffic.
"""
import torch
import torch.nn.functional as F
from torch.nn.attention import SDPBackend, sdpa_kernel

dev = torch.device("cuda")
torch.manual_seed(0)
H, Dh = 8, 64


def peak(fn):
    torch.cuda.synchronize()
    torch.cuda.empty_cache()
    torch.cuda.reset_peak_memory_stats()
    base = torch.cuda.memory_allocated()
    out = fn()
    torch.cuda.synchronize()
    return out, (torch.cuda.max_memory_allocated() - base) / 2**20


def gpu_ms(fn, reps=10):
    fn()
    torch.cuda.synchronize()
    a, b = torch.cuda.Event(enable_timing=True), torch.cuda.Event(enable_timing=True)
    a.record()
    for _ in range(reps):
        fn()
    b.record()
    torch.cuda.synchronize()
    return a.elapsed_time(b) / reps


def naive(q, k, v):
    s = (q @ k.transpose(-1, -2)) * Dh**-0.5             # (1, H, N, N) materialized in HBM
    return torch.softmax(s, dim=-1) @ v


print(f"== A. naive attention, 1 x {H} heads x N x {Dh}, fp16")
for n in (1024, 2048, 4096, 8192):
    q, k, v = (torch.randn(1, H, n, Dh, device=dev, dtype=torch.float16) for _ in range(3))
    try:
        _, mem = peak(lambda: naive(q, k, v))
        ms = gpu_ms(lambda: naive(q, k, v))
        print(f"  N={n:5d}  S alone = {H * n * n * 2 / 2**20:6.0f} MiB   peak extra {mem:7.0f} MiB   {ms:7.2f} ms")
    except torch.OutOfMemoryError:
        print(f"  N={n:5d}  S alone = {H * n * n * 2 / 2**20:6.0f} MiB   OutOfMemoryError on this 4 GB GPU")
    del q, k, v

print("== B. online softmax over key blocks (exact), N=2048, fp32")


def tiled(q, k, v, block=256):
    m = torch.full(q.shape[:-1] + (1,), float("-inf"), device=dev)       # running row max
    l = torch.zeros(q.shape[:-1] + (1,), device=dev)                     # running softmax denominator
    o = torch.zeros_like(q)                                              # running unnormalized output
    for j in range(0, k.shape[-2], block):
        s = (q @ k[..., j:j + block, :].transpose(-1, -2)) * Dh**-0.5    # only N x block scores at a time
        m_new = torch.maximum(m, s.amax(-1, keepdim=True))
        p = torch.exp(s - m_new)
        corr = torch.exp(m - m_new)                                      # rescale what was accumulated so far
        l = l * corr + p.sum(-1, keepdim=True)
        o = o * corr + p @ v[..., j:j + block, :]
        m = m_new
    return o / l


q, k, v = (torch.randn(1, H, 2048, Dh, device=dev) for _ in range(3))
ref, mem_ref = peak(lambda: naive(q, k, v))
out, mem_t = peak(lambda: tiled(q, k, v))
err = (out - ref).abs().max().item()
print(f"  max |tiled - exact| = {err:.1e};  peak extra memory: exact {mem_ref:.0f} MiB, tiled (block 256) {mem_t:.0f} MiB")
assert err < 1e-4 and mem_t < mem_ref / 2
del q, k, v, ref, out

print("== C. F.scaled_dot_product_attention backends, causal, N=4096, fp16")
n = 4096
q, k, v = (torch.randn(1, H, n, Dh, device=dev, dtype=torch.float16) for _ in range(3))
with sdpa_kernel(SDPBackend.MATH):
    ref = F.scaled_dot_product_attention(q, k, v, is_causal=True)
avail = []
for backend in (SDPBackend.FLASH_ATTENTION, SDPBackend.EFFICIENT_ATTENTION, SDPBackend.CUDNN_ATTENTION, SDPBackend.MATH):
    try:
        with sdpa_kernel(backend):
            out, mem = peak(lambda: F.scaled_dot_product_attention(q, k, v, is_causal=True))
            ms = gpu_ms(lambda: F.scaled_dot_product_attention(q, k, v, is_causal=True))
        err = (out.float() - ref.float()).abs().max().item()
        avail.append(backend.name)
        print(f"  {backend.name:20} {ms:7.2f} ms   peak extra {mem:6.0f} MiB   max |diff vs math| {err:.1e}")
    except RuntimeError as e:
        print(f"  {backend.name:20} not available in this build: {str(e).strip().splitlines()[0][:60]}")
assert "EFFICIENT_ATTENTION" in avail

print("== D. same FLOPs, different bytes (per head, N=4096, d=64, fp16)")
flops = 4 * n * n * Dh
s_bytes = n * n * 2
print(f"  FLOPs (QK^T and PV): {flops / 1e9:.1f} GFLOP for every method")
print(f"  naive: write S, read S, write P, read P = 4 x {s_bytes / 2**20:.0f} MiB = {4 * s_bytes / 2**20:.0f} MiB of HBM traffic")
for br in (64, 128):
    kv = 2 * n * Dh * 2 * (n // br)                      # K and V streamed once per block of br query rows
    print(f"  tiled with {br:3d} query rows per block: Q, O once + K, V {n // br} times = "
          f"{(2 * n * Dh * 2 + kv) / 2**20:.0f} MiB (the score tile stays in SRAM/registers)")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. naive attention, 1 x 8 heads x N x 64, fp16
  N= 1024  S alone =     16 MiB   peak extra      41 MiB      0.85 ms
  N= 2048  S alone =     64 MiB   peak extra     130 MiB      3.48 ms
  N= 4096  S alone =    256 MiB   peak extra     516 MiB     17.01 ms
  N= 8192  S alone =   1024 MiB   peak extra    2056 MiB     55.60 ms
== B. online softmax over key blocks (exact), N=2048, fp32
  max |tiled - exact| = 4.7e-07;  peak extra memory: exact 260 MiB, tiled (block 256) 68 MiB
== C. F.scaled_dot_product_attention backends, causal, N=4096, fp16
  FLASH_ATTENTION      not available in this build: No available kernel. Aborting execution.
  EFFICIENT_ATTENTION     1.92 ms   peak extra      4 MiB   max |diff vs math| 9.8e-04
  CUDNN_ATTENTION         1.75 ms   peak extra      4 MiB   max |diff vs math| 9.8e-04
  MATH                   51.70 ms   peak extra   1248 MiB   max |diff vs math| 0.0e+00
== D. same FLOPs, different bytes (per head, N=4096, d=64, fp16)
  FLOPs (QK^T and PV): 4.3 GFLOP for every method
  naive: write S, read S, write P, read P = 4 x 32 MiB = 128 MiB of HBM traffic
  tiled with  64 query rows per block: Q, O once + K, V 64 times = 65 MiB (the score tile stays in SRAM/registers)
  tiled with 128 query rows per block: Q, O once + K, V 32 times = 33 MiB (the score tile stays in SRAM/registers)
ALL ASSERTIONS PASSED
```

* **A**: naive attention's peak memory doubled each time N doubled (2× S + softmax temporaries): ~2 GiB at N = 8192 for one 8-head layer.
* **B**: the online-softmax recurrence in 15 lines of PyTorch is **exact** (4.7e-7) with ~4× less peak memory at N = 2048. In a fused kernel it also avoids the HBM traffic.
* **C**: the tiled backends were **~27× faster** than MATH with ~300× less extra memory. FLASH is missing from this build, so code that forces it (`sdpa_kernel(SDPBackend.FLASH_ATTENTION)`) fails here, and code that doesn't force it silently uses whatever is available.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | LoRA training starts from a worse model than the base | Step-0 loss > base loss | B not initialized to zero, or the scale applied twice | B = 0, `α/r` once | Assert step-0 output equals the base |
| F2 | LoRA learns slowly or not at all | Loss flat | Wrong target modules, tiny `α/r`, LR tuned for full FT | Target attention + MLP projections; LR ~10× full-FT; check `α/r` | Rank and LR sweep on a small run |
| F3 🔥 | int8 model accuracy collapses | Errors concentrated in a few channels | Outliers + per-tensor scales | Per-channel/group scales; LLM.int8() mixed decomposition; SmoothQuant for activations | Per-layer error report on calibration data |
| F4 🔥 | Quantized model is slower than fp16 | Profiler: dequant kernels + fp16 GEMM | No fused low-bit kernel for this shape/GPU | Use a fused kernel (tinygemm/Marlin/vendor); keep fp16 where none exists | Benchmark each kernel at serving batch sizes |
| F5 | int8 GEMM no faster than fp16 | Tensor-core TOPS below datasheet | Kernel/layout not tuned for the GPU | Measure; consider FP8 on Hopper/Ada; fall back to fp16 | Kernel-level benchmarks in CI |
| F6 🔥 | Long-context OOM "despite SDPA" | Peak ∝ N²; MATH backend in the trace | Silent fallback: unsupported dtype (fp32), arbitrary mask, head dim, or build | Run under `sdpa_kernel([EFFICIENT, CUDNN, FLASH])` to make fallback an error | Check backend selection in an integration test |
| F7 | Merged QLoRA model differs from the adapter model | Small output drift | Merged into a requantized NF4 base | Dequantize base to bf16, merge, serve bf16 (or requantize knowingly) | Parity test merged vs adapter |
| F8 ⚡ | QLoRA steps slower than LoRA | Dequant kernels per layer per forward | Inherent (4.6 vs 3.0 ms here) | Larger micro-batches amortize; fused dequant-matmul kernels | Budget time for memory saved |
| F9 | KV-cache OOM at modest batch | Memory ∝ batch × context | KV bytes per token × tokens (512 KiB/token for a 7B MHA model) | GQA models, KV quantization, paged KV cache, admission control | KV budget in capacity planning |

**Debugging toolkit.** `torch.cuda.max_memory_allocated()` around attention calls (an N² curve means MATH); `torch.nn.attention.sdpa_kernel(...)` to pin or forbid backends; `torch.profiler` kernel names (`flash`, `efficient_attention`, `cudnn`, `bmm`); per-layer quantization error reports (relative output error on calibration batches); `torch._inductor.utils.run_and_get_code` to see whether a dequant got fused; parameter counters (`sum(p.numel() for p in model.parameters() if p.requires_grad)`).

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why does LoRA work, and what exactly does it save?"</b></summary>

**Initial Prompt.** Justify LoRA over full fine-tuning for a team with limited GPUs.

**L5 Answer.** "It trains fewer parameters, so it uses less memory and is faster."

**Why L5 Crashes at Scale.** "Less memory" without the breakdown leads to wrong capacity plans. The frozen weights still have to be resident (and read every step), activations shrink much less than parameters (backward still flows through every frozen layer), and only optimizer state and gradients shrink proportionally.

**L7 Principal Defense.** Fine-tuning updates have low intrinsic rank, so ΔW ≈ BA with r ≪ d captures most of the change. LoRA stores r(d+k) trainable parameters per layer (1.56 % at r=8, d=k=1024). AdamW state shrinks the same (32 → 0.5 MiB measured) and gradients exist only for A and B. Activations fell 75 → 12.8 MiB here but don't vanish. Initialization with B = 0 makes step 0 the base model exactly, and `α/r` keeps the update scale stable across ranks. At serving time, merging (`W + (α/r)BA`, exact to 6.6e-7) removes all overhead, or adapters stay separate for multi-tenant serving. For a big model the memory win is optimizer state plus gradients; the weights themselves need quantization (QLoRA) or sharding.

</details>

<details><summary><b>Q2 · "Fine-tune a 65B model on one 48 GB GPU."</b></summary>

**Initial Prompt.** Budget is one 48 GB GPU; the model is 65B parameters.

**L5 Answer.** "Impossible; 65B in bf16 is 130 GB."

**Why L5 Crashes at Scale.** The arithmetic is right for bf16 weights and stops too early. It misses the QLoRA design point, which was demonstrated at exactly this size.

**L7 Principal Defense.** Budget like this. NF4 with double-quantized absmax costs 4.127 bits/param (verified by the listing), so 65B × 0.516 B ≈ 33.5 GB of frozen weights. LoRA adapters on all linear layers are a few hundred MB in bf16 plus fp32 optimizer state. Activations stay bounded with gradient checkpointing (06.2) and a micro-batch of 1, plus gradient accumulation. Paged optimizers absorb transient spikes. Compute runs in bf16 by dequantizing each layer just in time. That's QLoRA's 65B-on-48GB result. Costs to state upfront: ~1.5× slower steps from dequantization (4.6 vs 3.0 ms measured on a small model), and a quantization-noise floor that the paper found negligible on real benchmarks. Validate on your task before committing.

</details>

<details><summary><b>Q3 · "We quantized to int8 and accuracy fell off a cliff."</b></summary>

**Initial Prompt.** Per-tensor int8 post-training quantization of a 7B model; perplexity tripled.

**L5 Answer.** "int8 isn't enough precision for LLMs; use fp16."

**Why L5 Crashes at Scale.** int8 has plenty of precision for typical weights (per-channel output error 0.9 % measured). What failed is **scale granularity**. LLMs develop large-magnitude outlier features, and a single per-tensor scale stretched to cover them quantizes everything else to zero (measured: 93 % error on ordinary weights with 64 outliers in 16 M).

**L7 Principal Defense.** Use per-channel scales for weights and per-group for 4-bit, which confines an outlier's damage to its row or group (11.7 % and ~0 % added error measured). For activations, which have outlier *channels*, use LLM.int8()'s mixed decomposition (outlier columns in fp16, the rest int8) or SmoothQuant (migrate activation scale into the weights). For 4-bit, calibration-based methods (GPTQ, AWQ) choose rounding or scales from real activations. Validate per layer on calibration data and keep sensitive layers (embeddings, lm_head) in higher precision.

</details>

<details><summary><b>Q4 · "Our 4-bit model is slower than fp16."</b></summary>

**Initial Prompt.** After weight-only quantization, tokens/s dropped 3×.

**L5 Answer.** "Quantized models trade speed for memory."

**Why L5 Crashes at Scale.** At decode time the opposite should hold: batch-1 GEMV is bandwidth-bound, so 4× fewer weight bytes should be close to 4× faster. A slowdown means the implementation dequantizes to an fp16 copy in HBM and then runs a normal GEMV, moving more bytes than fp16 alone.

**L7 Principal Defense.** Measured on one 4096² layer: fp16 GEMV 202 µs; eager dequant-then-GEMV 1.15 ms (5.7× slower); `torch.compile` 513 µs; a **fused** int4 kernel that dequantizes in registers (PyTorch's tinygemm `_weight_int4pack_mm`) 82 µs, 2.5× faster than fp16. So the fix is a fused kernel matched to GPU and shape (tinygemm, Marlin-class kernels, vendor libraries), verified per batch size. Weight-only quantization helps memory-bound decode. Prefill and large batches are compute-bound and need W8A8 or FP8 tensor-core math to get faster.

</details>

<details><summary><b>Q5 · "Explain FlashAttention as if I'll implement it."</b></summary>

**Initial Prompt.** Why is FlashAttention faster if it does the same FLOPs?

**L5 Answer.** "It's a better CUDA kernel for attention."

**Why L5 Crashes at Scale.** That doesn't say what to look for when it isn't used, or why it matters more at long context.

**L7 Principal Defense.** Naive attention writes the N×N scores and probabilities to HBM and reads them back: bandwidth-bound and O(N²) memory (measured ~2 GiB at N = 8192 for one layer). FlashAttention tiles: a block of Q rows stays in SRAM while K/V blocks stream through, and softmax is computed **online**. Keep a running row max m and denominator l, and rescale the partial output when the max changes. That's the exact recurrence the listing implements in PyTorch (error 4.7e-7). S and P never reach HBM. Backward recomputes them from Q, K and the saved (m, l) instead of storing P, giving O(N) memory. FLOPs are unchanged (4N²d); HBM traffic drops from ~4N² values to roughly a pass over K/V per Q block (128 MiB → 33 MiB per head at N = 4096, d = 64). Measured: tiled backends ~27× faster than MATH with ~300× less memory.

</details>

<details><summary><b>Q6 · "We use SDPA, but long contexts still OOM."</b></summary>

**Initial Prompt.** A 16k-context fine-tune OOMs in attention, although the code calls `scaled_dot_product_attention`.

**L5 Answer.** "SDPA is FlashAttention, so the OOM must be elsewhere."

**Why L5 Crashes at Scale.** SDPA is a dispatcher over backends, not a guarantee of one. With an arbitrary float mask, fp32 inputs, an unsupported head dim, or a build without flash kernels (this Windows wheel: "No available kernel"), it **silently falls back** to MATH, which materializes N² scores (measured 1,248 MiB at N = 4096, 16× more at 16k).

**L7 Principal Defense.** Make the fallback loud. Wrap attention in `sdpa_kernel([SDPBackend.FLASH_ATTENTION, SDPBackend.EFFICIENT_ATTENTION, SDPBackend.CUDNN_ATTENTION])` in tests so MATH raises. Feed bf16/fp16. Use `is_causal=True` instead of a dense causal mask, and use supported head dims. Check peak memory vs N in a test (N² growth means fallback). If the mask is truly arbitrary, use FlexAttention (block-sparse masks compiled into a fused kernel) instead of a dense mask.

</details>

<details><summary><b>Q7 · "Serve 200 customer-specific LoRA adapters on one model."</b></summary>

**Initial Prompt.** Each tenant has its own fine-tuned adapter on a shared base.

**L5 Answer.** "Merge each adapter and deploy 200 model copies."

**Why L5 Crashes at Scale.** 200 merged copies of a 7B model is 2.7 TB of weights and 200 underutilized GPUs. Swapping merged weights per request costs seconds.

**L7 Principal Defense.** Keep the base weights shared and resident, keep adapters separate (r(d+k) per layer: MBs each), and batch requests from different tenants together. The base matmul is shared, and the per-request low-rank term is computed with gather-based batched kernels (the S-LoRA/Punica approach ⚠ not run here). Adapters live in a host-memory pool, and hot ones are cached on the GPU. Merge only for a single dominant tenant that needs the last bit of latency (merging is exact, as the listing shows). For QLoRA-trained adapters, serve on the same quantized base, or dequantize, merge and requantize with a parity check (F7).

</details>

<details><summary><b>Q8 · "int4, NF4 or FP8?"</b></summary>

**Initial Prompt.** Choose a weight format for a new inference fleet.

**L5 Answer.** "The smallest one, int4."

**Why L5 Crashes at Scale.** Format choice is a three-way trade between accuracy (distribution fit, scale overhead), kernel availability on the target GPUs, and whether the bottleneck is bandwidth or compute.

**L7 Principal Defense.** For memory-bound decode on any recent GPU, 4-bit weight-only formats with group scales win if a fused kernel exists (measured 2.5× over fp16). Among 4-bit formats, NF4 fit normally distributed weights better than uniform int4 (output error 9.2 % vs 11.7 % here) at 4.5 vs 4.125 bits before double quantization. Calibrated int4 (GPTQ/AWQ) usually closes the gap. For compute-bound prefill and training on Hopper/Ada, FP8 (E4M3/E5M2) tensor cores double throughput over bf16 with per-tensor or per-block scaling (⚠ not available on this Ampere GPU). Decide per workload: decode-heavy chat → int4 weight-only plus a quantized KV cache; prefill-heavy RAG → FP8.

</details>

<details><summary><b>Q9 · "What does the KV cache cost, and how do we fit more users?"</b></summary>

**Initial Prompt.** A 7B chat model on a 24 GB GPU serves only 4 concurrent 4k-token conversations.

**L5 Answer.** "Quantize the weights to 4-bit to make room."

**Why L5 Crashes at Scale.** Weights are only part of it. The KV cache grows with users × context: 512 KiB per token for a 32-layer, 32-head, 128-dim fp16 model, so 2 GiB per 4k-token sequence. Quantizing weights from 13.5 GB to ~3.5 GB buys ~5 more sequences, while a fragmented, preallocated cache wastes much of the rest.

**L7 Principal Defense.** Attack the cache directly. Grouped-query attention models (8 KV heads instead of 32: 4× smaller cache), int8/FP8 KV cache (2×), and **paged KV allocation** (vLLM's PagedAttention: fixed-size blocks allocated on demand, no per-sequence max-length preallocation, prefix sharing across requests) to remove fragmentation. Then admission control by KV budget and continuous batching (07.3) to keep the GPU busy. Quantized weights add room, but the binding constraint for concurrency is usually KV bytes.

</details>

---

## 5. Invariants Checklist

- [ ] LoRA: B = 0 at init, scale α/r, trainable r(d+k) per layer. Merge for zero-overhead serving.
- [ ] LoRA shrinks optimizer state and gradients proportionally, activations much less, frozen weights not at all.
- [ ] Quantization error is set by scale granularity. Outliers destroy per-tensor scales.
- [ ] NF4 + double quantization = 4.127 bits/param. QLoRA dequantizes per layer per forward.
- [ ] Weight-only low-bit formats speed up bandwidth-bound decode only with fused kernels; naive dequant is slower than fp16.
- [ ] FlashAttention = tiling + online softmax + recomputation: same FLOPs, O(N) memory, far less HBM traffic.
- [ ] SDPA falls back silently. Pin allowed backends in tests and watch for N² memory curves.
- [ ] The KV cache (bytes per token × tokens × users) usually caps serving concurrency, not the weights.

---

## 6. References

- E. Hu et al., "LoRA: Low-Rank Adaptation of Large Language Models", 2021 — https://arxiv.org/abs/2106.09685
- T. Dettmers et al., "QLoRA: Efficient Finetuning of Quantized LLMs", 2023 — https://arxiv.org/abs/2305.14314
- T. Dettmers et al., "LLM.int8(): 8-bit Matrix Multiplication for Transformers at Scale", 2022 — https://arxiv.org/abs/2208.07339
- G. Xiao et al., "SmoothQuant: Accurate and Efficient Post-Training Quantization for LLMs", 2022 — https://arxiv.org/abs/2211.10438
- E. Frantar et al., "GPTQ: Accurate Post-Training Quantization for Generative Pre-trained Transformers", 2022 — https://arxiv.org/abs/2210.17323
- J. Lin et al., "AWQ: Activation-aware Weight Quantization for LLM Compression and Acceleration", 2023 — https://arxiv.org/abs/2306.00978
- T. Dao et al., "FlashAttention: Fast and Memory-Efficient Exact Attention with IO-Awareness", 2022 — https://arxiv.org/abs/2205.14135
- T. Dao, "FlashAttention-2: Faster Attention with Better Parallelism and Work Partitioning", 2023 — https://arxiv.org/abs/2307.08691
- M. Milakov, N. Gimelshein, "Online normalizer calculation for softmax", 2018 — https://arxiv.org/abs/1805.02867
- W. Kwon et al., "Efficient Memory Management for Large Language Model Serving with PagedAttention", SOSP 2023 — https://arxiv.org/abs/2309.06180
- Y. Sheng et al., "S-LoRA: Serving Thousands of Concurrent LoRA Adapters", 2023 — https://arxiv.org/abs/2311.03285
- PyTorch docs: `scaled_dot_product_attention` — https://docs.pytorch.org/docs/stable/generated/torch.nn.functional.scaled_dot_product_attention.html
- PyTorch docs: `torch.nn.attention.sdpa_kernel` — https://docs.pytorch.org/docs/stable/generated/torch.nn.attention.sdpa_kernel.html
