# 07.1 · Distributed Training: DDP All-Reduce Rings vs FSDP/ZeRO Sharding & Tensor Parallelism

> **Folder 07 · Distributed Training, Fine-Tuning & Production ML Systems**
> **Measured on:** PyTorch 2.14.1 `torch.distributed` with the **gloo** backend over localhost TCP (Windows builds ship gloo only, no NCCL), 2–4 spawned CPU ranks on an i5-11260H (6C/12T), Windows 11. The NCCL/NVLink-scale numbers in this file come from the cost model, with assumed link parameters stated next to them.
> **Source quoted:** `torch/nn/parallel/distributed.py` and `torch/distributed/fsdp/_fully_shard/_fully_shard.py` from the installed wheel (tag `v2.14.1`). Memory formulas are checked against the ZeRO paper (Rajbhandari et al., SC 2020).

---

## 0. Orientation & the JVM/C++ Bridge

Training on many GPUs comes down to splitting three things: the **data** (each rank sees different samples), the **model state** (parameters, gradients, optimizer state) and the **computation of one layer**. Data parallelism (DDP) replicates state and all-reduces gradients. Sharded data parallelism (ZeRO/FSDP) partitions state and gathers it on demand. Tensor and pipeline parallelism split the model itself. Production LLM training composes all of them on a multi-dimensional device mesh. Every choice trades memory against bytes moved over a specific link.

| Distributed-training concept | JVM / big-data analogue | C++/HPC analogue |
|---|---|---|
| all-reduce (reduce-scatter + all-gather) | Spark `treeAggregate` / `reduceByKey` + broadcast | `MPI_Allreduce`, NCCL |
| DDP gradient buckets | batching small Kafka records into one produce request | message coalescing |
| ZeRO-3 / FSDP sharding | a partitioned cache (Hazelcast/Ignite) where each node owns a slice and fetches the rest on demand | distributed shared memory with prefetch |
| tensor parallelism | splitting one large join or matrix multiply across executors | ScaLAPACK block-distributed GEMM |
| pipeline parallelism | Kafka Streams / Flink topology stages, each on its own workers | a staged pipeline with bounded queues |
| DeviceMesh (DP × TP × PP) | a multi-level partitioning scheme | MPI Cartesian communicators |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 Collectives and the ring

```text
 all-reduce(S bytes, N ranks) = reduce-scatter + all-gather
 ring, N = 4, gradient split into 4 chunks; at step s rank r sends chunk (r - s) mod N to rank r+1:
   reduce-scatter, 3 steps:  each rank receives a chunk, adds its own, forwards → rank r ends owning reduced chunk r+1
   all-gather,     3 steps:  each rank forwards the reduced chunk it holds → every rank has every reduced chunk
 bytes sent per rank = 2 (N-1)/N · S   (→ 2S for large N: independent of N, so the ring is bandwidth-optimal)
 alpha-beta time:  ring          T ≈ 2(N-1)·α + 2(N-1)/N · S/B        latency term grows linearly with N
                   double tree   T ≈ 2·log2(N)·α + 2·S/B   (pipelined; NCCL picks tree for small/medium messages)
                   param server  T ≈ 2α + 2(N-1)·S/B      (the server's link carries everything)
 "bus bandwidth" (nccl-tests): busbw = S · 2(N-1)/N / T, comparable to the link speed regardless of N
```

The listing executes the ring on 4 simulated ranks and checks each rank's 96 bytes sent (= 2·3/4·64). With assumed α = 10 µs and B = 25 GB/s, a 1 GiB all-reduce costs ~75–96 ms on a ring of 8–512 GPUs but ~44 s through one parameter server. A 64 KiB all-reduce costs 10 ms on a 512-GPU ring and 0.19 ms on a tree, which is why NCCL switches algorithms by message size.

### 1.2 DDP: how gradients get averaged while backward still runs

```text
 construction: broadcast rank 0's parameters and buffers; group parameters into buckets in REVERSE registration order
               (≈ the order backward produces them); bucket_cap_mb default = _DEFAULT_BUCKET_CAP_MB = 25
               (distributed.py line 31); when the cap is left at its default the FIRST bucket is only
               dist._DEFAULT_FIRST_BUCKET_BYTES = 1 MiB, so the first all-reduce can start early
 per parameter: an autograd hook on its AccumulateGrad node marks the gradient ready (06.2)
 bucket full → launch an async all-reduce of the bucket's flat buffer while backward continues on other layers
 end of backward: wait for all buckets; gradients = sum / world_size (an average); optimizer steps identically everywhere
 after iteration 1: buckets are rebuilt in the order gradients actually became ready
 no_sync(): skip communication and accumulate locally (gradient accumulation); the next synced backward reduces the sum
```

Measured with 3 gloo ranks: DDP gradients equal one process on the full batch (asserted). An explicit 25 MB cap made **2** all-reduce calls per backward for 33.6 MB of gradients, and 4 MB made **8**. Four micro-batches made 8 calls, or **2** with `no_sync()` on the first three.

### 1.3 ZeRO stages and FSDP2

```text
 per-parameter bytes with mixed-precision AdamW (ZeRO paper, K = 12):
   bf16 param 2 + bf16 grad 2 + fp32 master param 4 + fp32 Adam m 4 + fp32 Adam v 4 = 16 bytes
 per GPU, Ψ parameters, N data-parallel ranks:
   DDP                     16Ψ
   ZeRO-1 (optimizer)      4Ψ + 12Ψ/N
   ZeRO-2 (+ gradients)    2Ψ + 14Ψ/N
   ZeRO-3 = FSDP full      16Ψ/N
 7.5B on 64 GPUs: 120 / 31.4 / 16.6 / 1.9 GB (the paper's Figure 1, reproduced and asserted by the listing)
 traffic per step: DDP and ZeRO-1/2 = 2Ψ elements; ZeRO-3 = 3Ψ (params all-gathered in forward AND backward)

 FSDP2 (torch.distributed.fsdp.fully_shard):
   each parameter → a DTensor sharded on dim 0 across the mesh (Shard(0))
   each fully_shard(module) call = one communication group: its parameters are all-gathered together
   pre-forward hook: all-gather the group (prefetching the next one) → forward → free the unsharded copy
                     (reshard_after_forward; default None = True except for the root module, _fully_shard.py:246)
   pre-backward: all-gather again → backward → reduce-scatter gradients → each rank keeps its gradient shard
   optimizer: steps on local shards only (its state is sharded too)
```

Measured with 2 gloo ranks: parameters and AdamW state were exactly **1/2 per rank** (2.00 + 4.01 MiB vs 4.01 + 8.02 MiB replicated). Five steps matched a single-process reference to 1e-6. Per step, `reshard_after_forward=True` issued **8 all-gathers** (4 layers × forward and backward) and 4 reduce-scatters, while `False` issued 4 all-gathers but kept the full weights alive between forward and backward (1,048,576 vs 524,288 elements per rank). The profiler also showed that **gloo has no native reduce-scatter**: each one ran as a `gloo:all_reduce`, about twice the bytes NCCL would move.

### 1.4 Tensor and pipeline parallelism

```text
 Megatron MLP, t ranks:  Y = GeLU(X A) B
   A split by COLUMNS [A1 .. At]: each rank computes GeLU(X A_i) locally (GeLU is elementwise: no sync needed)
   B split by ROWS    [B1 ; .. ; Bt]: each rank computes Z_i = GeLU(X A_i) B_i
   Y = Σ Z_i  → ONE all-reduce of a (batch·seq × hidden) activation per MLP, one per attention block, same in backward
   splitting A by rows instead would need a sum BEFORE the GeLU (listing: max error 36.9, since GeLU isn't additive)
 activation all-reduce size: b=8, s=2048, h=12288, bf16 → 384 MiB, 4x per layer per step → TP stays inside NVLink
 pipeline: layers in p stages, m micro-batches; idle "bubble" fraction ≈ (p-1)/(m+p-1)
 composition (DeviceMesh): TP inside a node (NVLink), PP across nodes, FSDP/DP outermost; HSDP = shard within a
                           node, replicate across nodes (reduce-scatter on the fast link, all-reduce on the slow one)
```

### 1.5 What this host can and can't show

There is no NCCL on Windows, and gloo over localhost TCP isn't a datacenter fabric. Measured bus bandwidth was **~0.45–0.9 GB/s** with 3–4 ranks for 1–64 MiB messages. ⚠ With exactly 2 ranks, all-reduces of 1 MiB and above were 5–10× slower (~15–19 ms for 1 MiB, ~0.15–0.2 GB/s). That's a transport artifact of this host whose cause wasn't isolated, and the DDP demonstrations use 3 ranks to avoid it. The protocols, the bucket counts, sharding, equivalence and the collective sequence are the same code paths production uses. Only the link speed differs.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 The arithmetic: ring, alpha-beta, ZeRO memory, Megatron split

```python
"""collective_cost_model.py - the arithmetic of data, ZeRO/FSDP and tensor parallelism, executed and checked.

A: ring all-reduce simulated on 4 ranks with NumPy: reduce-scatter then all-gather; bytes each rank sends.
B: alpha-beta cost model: ring vs pipelined tree vs one parameter server (link numbers are assumptions, stated).
C: memory per GPU for DDP and ZeRO-1/2/3 (= FSDP full sharding) with mixed-precision AdamW, checked against the
   ZeRO paper's 7.5B-parameter example, and the communication volume of each.
D: Megatron tensor parallelism: column-parallel A, row-parallel B; partial products + one all-reduce == the full MLP.
"""
import math

import numpy as np
import torch

print("== A. ring all-reduce, 4 ranks, a gradient of 8 int64 values (4 chunks of 2)")
N = 4
rng = np.random.default_rng(0)
data = [rng.integers(0, 10, size=8).astype(np.int64) for _ in range(N)]
expected = sum(data)
buf = [d.copy().reshape(N, -1) for d in data]
sent = [0] * N
for s in range(N - 1):                                   # reduce-scatter: rank r sends chunk (r - s) % N to r + 1
    msgs = [(r, (r - s) % N, buf[r][(r - s) % N].copy()) for r in range(N)]
    for r, c, payload in msgs:
        buf[(r + 1) % N][c] += payload
        sent[r] += payload.nbytes
for r in range(N):
    c = (r + 1) % N
    assert (buf[r][c] == expected.reshape(N, -1)[c]).all()
print("  after reduce-scatter (3 steps): " + ", ".join(f"rank {r} owns reduced chunk {(r + 1) % N}" for r in range(N)))
for s in range(N - 1):                                   # all-gather: rank r forwards chunk (r + 1 - s) % N to r + 1
    msgs = [(r, (r + 1 - s) % N, buf[r][(r + 1 - s) % N].copy()) for r in range(N)]
    for r, c, payload in msgs:
        buf[(r + 1) % N][c] = payload
        sent[r] += payload.nbytes
assert all((b.reshape(-1) == expected).all() for b in buf)
S = data[0].nbytes
print(f"  after all-gather (3 steps): every rank holds the sum {expected.tolist()}")
print(f"  bytes sent per rank: {sent} = 2(N-1)/N x {S} B = {2 * (N - 1) / N * S:.0f} B, independent of N for large N")
print(f"  naive gather-to-rank-0 + broadcast: rank 0's link carries {(N - 1) * S} B in and {(N - 1) * S} B out")

print("== B. alpha-beta model (assumed: alpha = 10 us per message, B = 25 GB/s per GPU link)")
alpha, bw = 10e-6, 25e9


def ring(size, n):
    return 2 * (n - 1) * alpha + 2 * (n - 1) / n * size / bw


def tree(size, n):                                       # pipelined double binary tree, large-message limit
    return 2 * math.log2(n) * alpha + 2 * size / bw


def param_server(size, n):                               # one server: its link carries everything
    return 2 * alpha + 2 * (n - 1) * size / bw


print(f"  {'message':>9} {'GPUs':>5} {'ring':>11} {'tree':>11} {'param server':>13}")
for size, label in ((64 * 2**10, "64 KiB"), (2**30, "1 GiB")):
    for n in (8, 64, 512):
        print(f"  {label:>9} {n:5d} {ring(size, n) * 1e3:9.3f}ms {tree(size, n) * 1e3:9.3f}ms "
              f"{param_server(size, n) * 1e3:11.1f}ms")
assert ring(2**30, 512) < 2 * ring(2**30, 8) and tree(64 * 2**10, 512) < ring(64 * 2**10, 512)

print("== C. memory per GPU: params + grads + AdamW state, bf16/fp16 mixed precision (K = 12 bytes of fp32 state)")


def zero(psi, n):
    return {"DDP (replicated)": 16 * psi, "ZeRO-1 (optimizer sharded)": 4 * psi + 12 * psi / n,
            "ZeRO-2 (+ gradients)": 2 * psi + 14 * psi / n, "ZeRO-3 / FSDP (+ parameters)": 16 * psi / n}


paper = zero(7.5e9, 64)
for (k, v), want in zip(paper.items(), (120.0, 31.4, 16.6, 1.9)):
    assert abs(v / 1e9 - want) < 0.06, (k, v)
print("  7.5B params on 64 GPUs (the ZeRO paper's Figure 1: 120 / 31.4 / 16.6 / 1.9 GB):")
for k, v in paper.items():
    print(f"    {k:30} {v / 1e9:7.1f} GB")
for psi, n in ((70e9, 8), (70e9, 64)):
    row = ", ".join(f"{k.split(' ')[0]} {v / 1e9:6.1f}" for k, v in zero(psi, n).items())
    print(f"  70B params on {n:2d} GPUs (GB): {row}")
print("  communication per step (elements of the model, x2 bytes in bf16):")
print("    DDP: all-reduce grads = reduce-scatter + all-gather = 2 x psi")
print("    ZeRO-1/2: reduce-scatter grads (psi) + all-gather updated params (psi) = 2 x psi (same as DDP)")
print("    ZeRO-3/FSDP: all-gather params in forward (psi) + again in backward (psi) + reduce-scatter grads (psi) = 3 x psi")

print("== D. tensor parallelism (Megatron MLP), 2 ranks simulated in one process")
torch.manual_seed(0)
X = torch.randn(8, 16, dtype=torch.float64)              # (batch*seq, hidden)
A = torch.randn(16, 64, dtype=torch.float64)             # hidden -> 4*hidden
Bm = torch.randn(64, 16, dtype=torch.float64)
full = torch.nn.functional.gelu(X @ A) @ Bm
A1, A2 = A[:, :32], A[:, 32:]                            # column-parallel: each rank owns half the columns of A
B1, B2 = Bm[:32], Bm[32:]                                # row-parallel: and the matching rows of B
Z1 = torch.nn.functional.gelu(X @ A1) @ B1               # rank 0, no communication needed so far
Z2 = torch.nn.functional.gelu(X @ A2) @ B2               # rank 1
assert torch.allclose(Z1 + Z2, full)                     # one all-reduce (sum) of an activation-sized tensor
print(f"  gelu(X A) B == all_reduce(gelu(X A_i) B_i): True (max |diff| {(Z1 + Z2 - full).abs().max().item():.1e})")
X1, X2, Ar1, Ar2 = X[:, :8], X[:, 8:], A[:8], A[8:]      # wrong split: A by rows needs a sum BEFORE the gelu
wrong = (torch.nn.functional.gelu(X1 @ Ar1) + torch.nn.functional.gelu(X2 @ Ar2)) @ Bm
print(f"  splitting A by rows instead: max |diff| {(wrong - full).abs().max().item():.1f} (gelu is not additive)")
b, s, h = 8, 2048, 12288
print(f"  cost: 1 all-reduce of b*s*h activations per MLP (and per attention block) in forward, 1 in backward;")
print(f"  e.g. b={b}, s={s}, h={h} in bf16 = {b * s * h * 2 / 2**20:.0f} MiB per all-reduce -> keep TP inside one NVLink node")
print("ALL ASSERTIONS PASSED")
```

Output (deterministic, verified):

```text
== A. ring all-reduce, 4 ranks, a gradient of 8 int64 values (4 chunks of 2)
  after reduce-scatter (3 steps): rank 0 owns reduced chunk 1, rank 1 owns reduced chunk 2, rank 2 owns reduced chunk 3, rank 3 owns reduced chunk 0
  after all-gather (3 steps): every rank holds the sum [18, 27, 21, 20, 17, 21, 23, 8]
  bytes sent per rank: [96, 96, 96, 96] = 2(N-1)/N x 64 B = 96 B, independent of N for large N
  naive gather-to-rank-0 + broadcast: rank 0's link carries 192 B in and 192 B out
== B. alpha-beta model (assumed: alpha = 10 us per message, B = 25 GB/s per GPU link)
    message  GPUs        ring        tree  param server
     64 KiB     8     0.145ms     0.065ms         0.1ms
     64 KiB    64     1.265ms     0.125ms         0.4ms
     64 KiB   512    10.225ms     0.185ms         2.7ms
      1 GiB     8    75.302ms    85.959ms       601.3ms
      1 GiB    64    85.817ms    86.019ms      5411.7ms
      1 GiB   512    95.952ms    86.079ms     43894.6ms
== C. memory per GPU: params + grads + AdamW state, bf16/fp16 mixed precision (K = 12 bytes of fp32 state)
  7.5B params on 64 GPUs (the ZeRO paper's Figure 1: 120 / 31.4 / 16.6 / 1.9 GB):
    DDP (replicated)                 120.0 GB
    ZeRO-1 (optimizer sharded)        31.4 GB
    ZeRO-2 (+ gradients)              16.6 GB
    ZeRO-3 / FSDP (+ parameters)       1.9 GB
  70B params on  8 GPUs (GB): DDP 1120.0, ZeRO-1  385.0, ZeRO-2  262.5, ZeRO-3  140.0
  70B params on 64 GPUs (GB): DDP 1120.0, ZeRO-1  293.1, ZeRO-2  155.3, ZeRO-3   17.5
  communication per step (elements of the model, x2 bytes in bf16):
    DDP: all-reduce grads = reduce-scatter + all-gather = 2 x psi
    ZeRO-1/2: reduce-scatter grads (psi) + all-gather updated params (psi) = 2 x psi (same as DDP)
    ZeRO-3/FSDP: all-gather params in forward (psi) + again in backward (psi) + reduce-scatter grads (psi) = 3 x psi
== D. tensor parallelism (Megatron MLP), 2 ranks simulated in one process
  gelu(X A) B == all_reduce(gelu(X A_i) B_i): True (max |diff| 4.3e-14)
  splitting A by rows instead: max |diff| 36.9 (gelu is not additive)
  cost: 1 all-reduce of b*s*h activations per MLP (and per attention block) in forward, 1 in backward;
  e.g. b=8, s=2048, h=12288 in bf16 = 384 MiB per all-reduce -> keep TP inside one NVLink node
ALL ASSERTIONS PASSED
```

* The ring's per-rank traffic is 2(N-1)/N·S, flat in N. The **parameter server is the slow trap**: its link carries 2(N-1)·S, ~44 s per GiB at 512 GPUs against ~0.1 s for a ring.
* For small messages the ring's linear latency term dominates (10 ms for 64 KiB on 512 GPUs), so collective libraries switch to trees. Many tiny all-reduces are the other trap, which is why DDP buckets them.
* ZeRO-3 brings a 7.5B model's training state from 120 GB to 1.9 GB per GPU at 64 ranks. 70B needs 1120 GB per GPU replicated (impossible) but 17.5 GB fully sharded across 64 GPUs, before activations.

### 2.2 Real DDP across processes

```python
"""ddp_gloo_processes.py - real DistributedDataParallel across processes (gloo over localhost TCP, CPU tensors).

A: all_reduce cost vs message size on 2, 3 and 4 ranks: latency-bound small messages, bandwidth-bound large ones.
B: DDP correctness: 3 ranks x a third of the batch produce the same gradients as one process on the full batch.
C: gradient buckets: how many all-reduces one backward issues (bucket_cap_mb), and no_sync() for accumulation.
D: step time with and without DDP's communication for an 8.4M-parameter MLP.
Each rank is a spawned process (Windows: gloo only, no NCCL); CUDA is hidden from the workers.
"""
import os
import socket
import time

import torch
import torch.distributed as dist
import torch.multiprocessing as mp
from torch.distributed.algorithms.ddp_comm_hooks.default_hooks import allreduce_hook
from torch.nn.parallel import DistributedDataParallel as DDP


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def mlp(width=1024, depth=8):
    torch.manual_seed(0)
    return torch.nn.Sequential(*[m for _ in range(depth) for m in (torch.nn.Linear(width, width), torch.nn.ReLU())])


def bench_allreduce(rank, world):
    rows = []
    for size in (2**16, 2**20, 2**24, 2**26):
        t = torch.ones(size // 4)
        reps = 30 if size <= 2**20 else 5
        dist.all_reduce(t)
        dist.barrier()
        t0 = time.perf_counter()
        for _ in range(reps):
            dist.all_reduce(t)
        dt = (time.perf_counter() - t0) / reps
        rows.append((size, dt, size * 2 * (world - 1) / world / dt / 1e9))
    return rows


def worker(rank, world, port, part):
    torch.set_num_threads(max(1, 6 // world))
    dist.init_process_group("gloo", init_method=f"tcp://127.0.0.1:{port}", rank=rank, world_size=world)
    out = []
    rows = bench_allreduce(rank, world)
    if rank == 0:
        for size, dt, busbw in rows:
            label = f"{size // 2**20} MiB" if size >= 2**20 else f"{size // 2**10} KiB"
            out.append(f"  world={world}  all_reduce {label:>7}: {dt * 1e3:8.3f} ms   bus bandwidth {busbw:6.2f} GB/s")
    if part == "all":
        gen = torch.Generator().manual_seed(1)
        x, y = torch.randn(32 * world, 1024, generator=gen), torch.randn(32 * world, 1024, generator=gen)
        model = DDP(mlp())
        shard = slice(rank * 32, rank * 32 + 32)
        torch.nn.functional.mse_loss(model(x[shard]), y[shard]).backward()
        grads = [p.grad for p in model.parameters()]
        if rank == 0:
            ref = mlp()
            torch.nn.functional.mse_loss(ref(x), y).backward()
            ok = all(torch.allclose(g, r.grad, rtol=1e-4, atol=1e-6) for g, r in zip(grads, ref.parameters()))
            n = sum(p.numel() for p in ref.parameters())
            out.append(f"== B. DDP gradients ({world} ranks x 32 rows) == single process ({32 * world} rows): {ok}   "
                       f"({n / 1e6:.1f}M params)")
            assert ok
        calls = {"n": 0, "bytes": 0}

        def counting_hook(state, bucket):
            calls["n"] += 1
            calls["bytes"] += bucket.buffer().numel() * bucket.buffer().element_size()
            return allreduce_hook(state, bucket)

        if rank == 0:
            out.append("== C. all-reduce calls per backward (gradients = 33.6 MB fp32)")
        for cap in (25, 4):
            model = DDP(mlp(), bucket_cap_mb=cap)
            model.register_comm_hook(None, counting_hook)
            for step in range(2):                        # bucket layout is rebuilt after the first iteration
                calls["n"] = calls["bytes"] = 0
                torch.nn.functional.mse_loss(model(x[shard]), y[shard]).backward()
            if rank == 0:
                out.append(f"  bucket_cap_mb={cap:2d}: {calls['n']:2d} all-reduce calls, {calls['bytes'] / 1e6:.1f} MB total")
        for use_no_sync in (False, True):
            model = DDP(mlp())
            model.register_comm_hook(None, counting_hook)
            torch.nn.functional.mse_loss(model(x[shard]), y[shard]).backward()    # warm-up: buckets get rebuilt
            calls["n"] = 0
            for micro in range(4):
                if use_no_sync and micro < 3:
                    with model.no_sync():                # accumulate locally, no communication
                        torch.nn.functional.mse_loss(model(x[shard]), y[shard]).backward()
                else:
                    torch.nn.functional.mse_loss(model(x[shard]), y[shard]).backward()
            if rank == 0:
                label = "no_sync() on the first 3" if use_no_sync else "plain backward each time "
                out.append(f"  4 micro-batches, {label}: {calls['n']} all-reduce calls")
        if rank == 0:
            out.append("== D. training step time, batch 32 per rank, SGD")
        for label, wrap in (("local model, no communication", False), ("DDP (all-reduce overlapped with backward)", True)):
            net = mlp()
            model = DDP(net) if wrap else net
            opt = torch.optim.SGD(model.parameters(), lr=1e-3)

            def step():
                opt.zero_grad(set_to_none=True)
                torch.nn.functional.mse_loss(model(x[shard]), y[shard]).backward()
                opt.step()

            step()
            dist.barrier()
            t0 = time.perf_counter()
            for _ in range(10):
                step()
            dt = (time.perf_counter() - t0) / 10
            if rank == 0:
                out.append(f"  {label:42} {dt * 1e3:7.1f} ms/step")
    if rank == 0:
        print("\n".join(out), flush=True)
    dist.destroy_process_group()


if __name__ == "__main__":
    os.environ["CUDA_VISIBLE_DEVICES"] = ""                # workers inherit it: CPU-only ranks
    print("== A. all_reduce over gloo (localhost TCP), float32 tensors", flush=True)
    for world in (2, 4):
        mp.spawn(worker, args=(world, free_port(), "bench"), nprocs=world)
    mp.spawn(worker, args=(3, free_port(), "all"), nprocs=3)
    print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. all_reduce over gloo (localhost TCP), float32 tensors
  world=2  all_reduce  64 KiB:    0.483 ms   bus bandwidth   0.14 GB/s
  world=2  all_reduce   1 MiB:   19.247 ms   bus bandwidth   0.05 GB/s
  world=2  all_reduce  16 MiB:   80.111 ms   bus bandwidth   0.21 GB/s
  world=2  all_reduce  64 MiB:  424.404 ms   bus bandwidth   0.16 GB/s
  world=4  all_reduce  64 KiB:    1.503 ms   bus bandwidth   0.07 GB/s
  world=4  all_reduce   1 MiB:    2.176 ms   bus bandwidth   0.72 GB/s
  world=4  all_reduce  16 MiB:   30.822 ms   bus bandwidth   0.82 GB/s
  world=4  all_reduce  64 MiB:  156.372 ms   bus bandwidth   0.64 GB/s
  world=3  all_reduce  64 KiB:    1.313 ms   bus bandwidth   0.07 GB/s
  world=3  all_reduce   1 MiB:    1.876 ms   bus bandwidth   0.75 GB/s
  world=3  all_reduce  16 MiB:   34.511 ms   bus bandwidth   0.65 GB/s
  world=3  all_reduce  64 MiB:  127.404 ms   bus bandwidth   0.70 GB/s
== B. DDP gradients (3 ranks x 32 rows) == single process (96 rows): True   (8.4M params)
== C. all-reduce calls per backward (gradients = 33.6 MB fp32)
  bucket_cap_mb=25:  2 all-reduce calls, 33.6 MB total
  bucket_cap_mb= 4:  8 all-reduce calls, 33.6 MB total
  4 micro-batches, plain backward each time : 8 all-reduce calls
  4 micro-batches, no_sync() on the first 3: 2 all-reduce calls
== D. training step time, batch 32 per rank, SGD
  local model, no communication                 27.1 ms/step
  DDP (all-reduce overlapped with backward)    114.5 ms/step
ALL ASSERTIONS PASSED
```

* **A**: latency-bound below ~64 KiB (0.5–1.5 ms regardless of size), bandwidth-bound above 1 MiB. Note the 2-rank cliff (§1.5).
* **B**: data parallelism is exact. The averaged gradients of 3 × 32 rows equal those of 96 rows in one process.
* **C**: bucket count follows `bucket_cap_mb`. `no_sync()` cut communication 4× for 4-way gradient accumulation.
* **D**: on this ~0.5–0.9 GB/s "network", DDP made the step **~4–4.5× slower** (25–27 → 114–123 ms), because 33.6 MB of gradients per step at ~0.7 GB/s busbw takes ~65 ms and overlap can't hide more than backward's duration. That's DDP on a slow link: when communication exceeds backward time, scaling stops. On NVLink (hundreds of GB/s) the same all-reduce takes well under a millisecond.

### 2.3 FSDP2 sharding, equivalence and collectives

```python
"""fsdp2_sharding.py - FSDP2 (fully_shard, ZeRO-3) across 2 processes on gloo/CPU: shards, equivalence, collectives.

A: what each rank stores: parameters become DTensors sharded on dim 0; AdamW state is sharded the same way.
B: equivalence: 5 AdamW steps with FSDP2 (each rank half the batch) == one process on the full batch.
C: collectives per training step (torch.profiler): all-gathers and reduce-scatters, reshard_after_forward True/False.
D: what lives between forward and backward: resharded DTensor shards vs unsharded full parameters.
"""
import collections
import os
import socket

import torch
import torch.distributed as dist
import torch.multiprocessing as mp
from torch.distributed.device_mesh import init_device_mesh
from torch.distributed.fsdp import fully_shard

W, L = 512, 4


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def build():
    torch.manual_seed(0)
    return torch.nn.Sequential(*[m for _ in range(L) for m in (torch.nn.Linear(W, W), torch.nn.ReLU())])


def sharded(mesh, reshard=True):
    model = build()
    for layer in model:
        if isinstance(layer, torch.nn.Linear):
            fully_shard(layer, mesh=mesh, reshard_after_forward=reshard)
    fully_shard(model, mesh=mesh, reshard_after_forward=reshard)
    return model


def local_bytes(tensors):
    return sum((t.to_local() if hasattr(t, "to_local") else t).numel() * t.element_size() for t in tensors)


def worker(rank, world, port):
    torch.set_num_threads(2)
    dist.init_process_group("gloo", init_method=f"tcp://127.0.0.1:{port}", rank=rank, world_size=world)
    mesh = init_device_mesh("cpu", (world,))
    out = []
    model = sharded(mesh)
    opt = torch.optim.AdamW(model.parameters(), lr=1e-2)
    w0 = model[0].weight
    if rank == 0:
        out.append("== A. what rank 0 stores")
        out.append(f"  model[0].weight: {type(w0).__name__}, placement {w0.placements}, global {tuple(w0.shape)}, "
                   f"local {tuple(w0.to_local().shape)}")
    gen = torch.Generator().manual_seed(1)
    x, y = torch.randn(64, W, generator=gen), torch.randn(64, W, generator=gen)
    half = slice(rank * 32, rank * 32 + 32)
    ref = build() if rank == 0 else None
    ref_opt = torch.optim.AdamW(ref.parameters(), lr=1e-2) if ref is not None else None
    losses, ref_losses = [], []
    for step in range(5):
        opt.zero_grad(set_to_none=True)
        loss = torch.nn.functional.mse_loss(model(x[half]), y[half])
        loss.backward()
        opt.step()
        g = loss.detach().clone()
        dist.all_reduce(g)
        losses.append(g.item() / world)
        if ref is not None:
            ref_opt.zero_grad(set_to_none=True)
            r = torch.nn.functional.mse_loss(ref(x), y)
            r.backward()
            ref_opt.step()
            ref_losses.append(r.item())
    full_w = model[0].weight.full_tensor()               # all-gather of the shards (a collective: every rank calls it)
    if rank == 0:
        n = sum(p.numel() for p in ref.parameters())
        p_bytes = local_bytes(model.parameters())
        s_bytes = local_bytes([v for st in opt.state.values() for v in st.values() if v.dim() > 0])
        out.append(f"  per rank: parameters {p_bytes / 2**20:.2f} MiB, AdamW state {s_bytes / 2**20:.2f} MiB "
                   f"(a DDP replica: {n * 4 / 2**20:.2f} MiB + {2 * n * 4 / 2**20:.2f} MiB) -> 1/{world} each")
        assert abs(p_bytes - n * 4 / world) < 1 and abs(s_bytes - 2 * n * 4 / world) < 1
        out.append("== B. 5 AdamW steps: FSDP2 (2 ranks x 32 rows) vs one process (64 rows)")
        out.append(f"  FSDP2 loss:     {', '.join(f'{v:.6f}' for v in losses)}")
        out.append(f"  reference loss: {', '.join(f'{v:.6f}' for v in ref_losses)}")
        ok = all(abs(a - b) < 1e-5 for a, b in zip(losses, ref_losses)) and torch.allclose(full_w, ref[0].weight, atol=1e-5)
        out.append(f"  losses and full_tensor() of layer 0 match the reference: {ok}")
        assert ok
        out.append("== C. collectives in one training step (4 sharded Linear layers)")
    keys = ("c10d::_allgather_base_", "c10d::_reduce_scatter_base_", "gloo:all_gather", "gloo:all_reduce")
    for reshard in (True, False):
        m = sharded(mesh, reshard)
        m(x[half]).sum().backward()                      # warm-up
        with torch.profiler.profile(activities=[torch.profiler.ProfilerActivity.CPU]) as prof:
            m(x[half]).sum().backward()
        c = collections.Counter(e.name for e in prof.events() if e.name in keys)
        h = m(x[half])
        kept = [type(layer.weight).__name__ + str(tuple(layer.weight.shape)) for layer in m if isinstance(layer, torch.nn.Linear)][:1]
        held = sum(layer.weight.numel() if not hasattr(layer.weight, "to_local") else layer.weight.to_local().numel()
                   for layer in m if isinstance(layer, torch.nn.Linear))
        h.sum().backward()
        if rank == 0:
            out.append(f"  reshard_after_forward={reshard!s:5}: all-gather {c['c10d::_allgather_base_']}, "
                       f"reduce-scatter {c['c10d::_reduce_scatter_base_']} (gloo ran them as all_gather "
                       f"{c['gloo:all_gather']}, all_reduce {c['gloo:all_reduce']})")
            if reshard:
                out_d = [f"== D. registered weights between forward and backward (rank 0)"]
            out_d.append(f"  reshard_after_forward={reshard!s:5}: layer 0 weight is {kept[0]}; "
                         f"weight elements held by this rank {held:,}")
    if rank == 0:
        out.extend(out_d)
        print("\n".join(out), flush=True)
    dist.destroy_process_group()


if __name__ == "__main__":
    os.environ["CUDA_VISIBLE_DEVICES"] = ""
    mp.spawn(worker, args=(2, free_port()), nprocs=2)
    print("ALL ASSERTIONS PASSED")
```

Output (deterministic, verified):

```text
== A. what rank 0 stores
  model[0].weight: DTensor, placement (Shard(dim=0),), global (512, 512), local (256, 512)
  per rank: parameters 2.00 MiB, AdamW state 4.01 MiB (a DDP replica: 4.01 MiB + 8.02 MiB) -> 1/2 each
== B. 5 AdamW steps: FSDP2 (2 ranks x 32 rows) vs one process (64 rows)
  FSDP2 loss:     1.006937, 1.468044, 1.003632, 1.003718, 1.001486
  reference loss: 1.006936, 1.468044, 1.003632, 1.003718, 1.001486
  losses and full_tensor() of layer 0 match the reference: True
== C. collectives in one training step (4 sharded Linear layers)
  reshard_after_forward=True : all-gather 8, reduce-scatter 4 (gloo ran them as all_gather 8, all_reduce 4)
  reshard_after_forward=False: all-gather 4, reduce-scatter 4 (gloo ran them as all_gather 4, all_reduce 4)
== D. registered weights between forward and backward (rank 0)
  reshard_after_forward=True : layer 0 weight is DTensor(512, 512); weight elements held by this rank 524,288
  reshard_after_forward=False: layer 0 weight is Parameter(512, 512); weight elements held by this rank 1,048,576
ALL ASSERTIONS PASSED
```

* Every parameter is a `DTensor` with placement `Shard(dim=0)`. Each rank physically holds half the rows, and the AdamW state follows the same sharding.
* Losses match the reference at the 6th decimal: sharding changes where bytes live, not the math.
* `reshard_after_forward` is the ZeRO-3 vs ZeRO-2-like switch: 8 vs 4 all-gathers per step in exchange for holding full weights between forward and backward.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Job hangs, then a collective timeout | Some ranks in `all_reduce`, others elsewhere | Ranks issue collectives in different orders (rank-conditional code, uneven data) | Make every rank call the same collectives in the same order; drop the last uneven batch | `TORCH_DISTRIBUTED_DEBUG=DETAIL`; NCCL flight recorder (`TORCH_NCCL_TRACE_BUFFER_SIZE`) dumps |
| F2 | `Expected to have finished reduction in the prior iteration` | DDP error at step 2 | Parameters unused in forward never become ready | Remove unused params or `find_unused_parameters=True` (extra graph traversal per step) | `static_graph=True` when the graph is fixed |
| F3 ⚡ | Scaling efficiency drops past 8–16 GPUs | Step time grows with N; GPU idle during backward | Communication not hidden: slow links, bad buckets, small batch per GPU | Bigger per-GPU batch, tune `bucket_cap_mb`, HSDP, bf16 gradient compression hook | Measure busbw (nccl-tests) and compute/comm overlap in traces |
| F4 🔥 | OOM only on rank 0 | Rank 0 loads or saves full state | Full `state_dict` gathered on one rank | `torch.distributed.checkpoint` (sharded save/load) | Never materialize full state on one rank for sharded models |
| F5 | Silent overfitting / wrong epoch size | Each rank sees all data | No `DistributedSampler`, or `set_epoch` not called | `DistributedSampler(shuffle=True)` + `sampler.set_epoch(epoch)` | Assert sample IDs differ across ranks in a test |
| F6 | Accuracy differs from single-GPU | BatchNorm with small per-GPU batches | BN statistics are per rank | `SyncBatchNorm`, or LayerNorm/GroupNorm | Choose norms with the distribution plan |
| F7 | Loss differs slightly between 8 and 16 GPUs | 1e-6-level drift | Floating-point sum order changes with world size | Expected. Use deterministic algorithms only where reproducibility is required | Compare runs with tolerances |
| F8 ⚡ | Tensor parallel across nodes is slow | All-reduces on InfiniBand dominate | TP moves activations 4× per layer | Keep TP inside the NVLink domain; use PP or FSDP across nodes | Map mesh dimensions to link speeds |
| F9 🔥 | FSDP OOM despite sharding | Peak during forward of one big layer | One wrapped unit holds a huge unsharded group | Wrap finer (per transformer block), checkpoint activations | Size units: largest group × 2 (prefetch) must fit |
| F10 ⚠ | Windows: `ProcessGroupNCCL` unavailable; 2-rank gloo slow | — | Windows builds ship gloo only | Develop on Linux/WSL2 for multi-GPU; gloo for CPU tests | Keep CI multi-process tests on gloo, perf tests on Linux |

**Debugging toolkit.** `TORCH_DISTRIBUTED_DEBUG=DETAIL` (collective fingerprint checks); `NCCL_DEBUG=INFO` (topology and algorithm choice); `TORCH_NCCL_TRACE_BUFFER_SIZE` + flight-recorder dumps on timeout; `torch.profiler` with `record_shapes` (collective events by name: `c10d::_allgather_base_`, `gloo:all_reduce`, as in the listing); nccl-tests `all_reduce_perf` for busbw; `torch.distributed.breakpoint()` for single-rank pdb.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Explain ring all-reduce and why every framework uses it."</b></summary>

**Initial Prompt.** How are gradients averaged across 1,024 GPUs, and why not a parameter server?

**L5 Answer.** "Each GPU sends its gradients to a master, which averages and broadcasts them."

**Why L5 Crashes at Scale.** The master's link carries 2(N-1)·S bytes per step. For a 1 GiB gradient on 512 GPUs that's ~44 s per step at 25 GB/s (cost model), and it grows linearly with N. Adding GPUs makes training slower.

**L7 Principal Defense.** All-reduce = reduce-scatter + all-gather. In a ring, each rank sends one chunk per step to its neighbour: N-1 steps to reduce-scatter (each rank ends owning one fully reduced chunk), N-1 steps to all-gather. Each rank sends 2(N-1)/N·S bytes, flat in N, so it's bandwidth-optimal (the listing checks 96 B per rank for 64 B on 4 ranks). The cost is a latency term linear in N (2(N-1)·α), so for small messages NCCL uses pipelined double binary trees (log N latency). Real systems choose by message size and topology. Report bus bandwidth (busbw = S·2(N-1)/N/T) so you can compare to link speed.

</details>

<details><summary><b>Q2 · "DDP or FSDP for our 7B model?"</b></summary>

**Initial Prompt.** 64 × 80 GB GPUs, a 7.5B-parameter model, AdamW, bf16.

**L5 Answer.** "DDP. It's simpler and the model fits in 80 GB."

**Why L5 Crashes at Scale.** The weights fit (15 GB in bf16), but training state doesn't: 16 bytes per parameter = 120 GB per GPU under DDP before activations. The job OOMs at the first optimizer step.

**L7 Principal Defense.** Do the arithmetic (listing, matching the ZeRO paper): DDP 120 GB, ZeRO-1 31.4 GB, ZeRO-2 16.6 GB, ZeRO-3/FSDP 1.9 GB per GPU at 64 ranks. ZeRO-1/2 cost the same 2Ψ traffic as DDP; full sharding costs 3Ψ (1.5×) because parameters are all-gathered in forward and again in backward. Choose the least sharding that fits with activations and headroom: here ZeRO-2-like (`reshard_after_forward=False` in FSDP2, which skips the backward all-gather; measured 4 vs 8 all-gathers per step) or full FSDP if activation memory needs the room. Across nodes use HSDP (shard within a node, replicate across) so the 3Ψ traffic stays on NVLink.

</details>

<details><summary><b>Q3 · "We went from 8 to 64 GPUs and throughput rose only 3×."</b></summary>

**Initial Prompt.** DDP training of a 1B model; per-GPU batch fixed at 8.

**L5 Answer.** "Network congestion. Buy faster InfiniBand."

**Why L5 Crashes at Scale.** It might help, but without measurement it could be the wrong bottleneck. A small per-GPU batch makes backward short, so there's no time to hide the all-reduce. The ring's latency term grows with N. Or stragglers (one slow rank, data loading) set the pace for everyone.

**L7 Principal Defense.** Decompose step time: compute, exposed communication (trace: all-reduce kernels after backward ends), and waits at collectives (stragglers). Check busbw against link speed with nccl-tests. Then fix the right thing. If exposed communication dominates: larger per-GPU batch or accumulation with `no_sync` (measured 4× fewer calls), bf16 gradient compression hooks, tuned buckets, HSDP to keep most traffic intra-node. If stragglers: input pipeline (06.4), thermal throttling, a bad host. The listing shows the extreme case: on a ~0.5–0.9 GB/s link DDP was 4–4.5× slower than local compute. When communication exceeds backward time, adding ranks makes things worse.

</details>

<details><summary><b>Q4 · "How does DDP overlap communication with computation?"</b></summary>

**Initial Prompt.** Walk through DDP's backward at the hook level.

**L5 Answer.** "It all-reduces the gradients after backward finishes."

**Why L5 Crashes at Scale.** That design idles the network during backward and the GPU during communication, wasting up to half the step on large models.

**L7 Principal Defense.** DDP registers a hook on each parameter's `AccumulateGrad` node (the autograd engine, 06.2). Parameters are grouped into buckets of ~25 MB (`_DEFAULT_BUCKET_CAP_MB`) in reverse order, which approximates the order gradients are produced. When the cap is left at default, the first bucket is only 1 MiB so communication starts as early as possible. When every gradient in a bucket is ready, an asynchronous all-reduce launches while backward computes earlier layers. After iteration 1 the buckets are rebuilt in the observed ready order. Trade-off: big buckets mean fewer, more efficient collectives but later start; small buckets mean earlier start but more latency (measured: 2 calls at 25 MB vs 8 at 4 MB for the same 33.6 MB). Unused parameters break the "all ready" accounting, which is F2.

</details>

<details><summary><b>Q5 · "Can we train a 70B model on 64 × 80 GB GPUs?"</b></summary>

**Initial Prompt.** Plan the parallelism for a 70B dense transformer.

**L5 Answer.** "Yes, with FSDP. Sharding divides everything by 64."

**Why L5 Crashes at Scale.** FSDP shards parameters, gradients and optimizer state (17.5 GB per GPU at 64 ranks, from the listing), not **activations**, which scale with batch × sequence × hidden × layers. Each FSDP unit is also gathered in full before its forward, and the largest unit plus the prefetched next one must fit.

**L7 Principal Defense.** Budget per GPU: 17.5 GB of sharded state, unsharded working set for the largest unit (×2 with prefetch), activations under selective checkpointing, and headroom for fragmentation (06.4). If activations don't fit, add tensor parallelism inside each 8-GPU node (which divides per-layer activations and weights by 8, at 4 activation all-reduces per layer on NVLink), with FSDP across the 8 nodes. Add sequence or context parallelism for long contexts, and pipeline parallelism if the cross-node fabric is slow. Express it as a 2-D DeviceMesh (dp=8, tp=8) and validate with a one-step dry run that records peak memory per rank.

</details>

<details><summary><b>Q6 · "Why not tensor-parallelize across all 64 GPUs instead of sharding?"</b></summary>

**Initial Prompt.** Someone proposes TP=64 to minimize memory.

**L5 Answer.** "More TP ranks means smaller matrices per GPU, so it's faster."

**Why L5 Crashes at Scale.** TP communicates **activations** on the critical path: two all-reduces per layer in forward and two in backward, each b·s·h elements (384 MiB in bf16 for b=8, s=2048, h=12288). Across InfiniBand that's tens of milliseconds per layer, and the per-GPU matrices become too thin for tensor cores to run efficiently.

**L7 Principal Defense.** The listing shows why TP needs exactly one all-reduce per MLP (column-parallel A, row-parallel B: GeLU stays local) and why the other split fails (GeLU isn't additive). That all-reduce is synchronous with compute, so TP belongs where links are fastest: inside the NVLink domain, TP ≤ 8 typically. Scale the remaining factor with data/FSDP parallelism, whose gradient traffic can overlap with backward, or pipeline parallelism, which sends only boundary activations point to point. The rule: map each parallelism dimension to the link whose bandwidth matches its traffic pattern.

</details>

<details><summary><b>Q7 · "Implement gradient accumulation correctly under DDP."</b></summary>

**Initial Prompt.** Effective batch 1,024 = 8 GPUs × 32 × 4 micro-batches.

**L5 Answer.** "Call `backward()` four times, then `optimizer.step()`."

**Why L5 Crashes at Scale.** Correct math, wasted communication: DDP all-reduces on every `backward()`, 4× the traffic (measured 8 calls instead of 2). And if the loss isn't divided by the number of micro-batches, the effective learning rate is 4× too high.

**L7 Principal Defense.** Wrap the first three backwards in `model.no_sync()` and run the fourth normally. The final all-reduce reduces the locally accumulated sum (measured: 2 all-reduce calls instead of 8). Scale each micro-batch loss by 1/4, or use a summed loss with an adjusted LR consistently. Under FSDP2 the equivalent is `set_requires_gradient_sync(False)` on the micro-steps, which trades memory (unsharded gradient accumulation) for communication. Verify on a small model that accumulated gradients equal the large-batch gradients, the same check the listing does for DDP.

</details>

<details><summary><b>Q8 · "Our 512-GPU job hangs at step 0 with no error."</b></summary>

**Initial Prompt.** All ranks start; nothing progresses; after 30 minutes the NCCL watchdog kills the job.

**L5 Answer.** "Increase the timeout and restart."

**Why L5 Crashes at Scale.** A hang is almost always a **collective mismatch**: some ranks called a collective others didn't (rank-conditional logging that calls `all_reduce`, an `if` on local data, a different number of batches per rank), or ranks called collectives in a different order. A longer timeout only delays the failure and burns 512 GPU-hours each time.

**L7 Principal Defense.** Make the hang diagnosable. Enable the NCCL flight recorder so each rank dumps its last collectives on timeout, then compare sequence numbers across ranks to find the first divergence. Use `TORCH_DISTRIBUTED_DEBUG=DETAIL` in staging to check collective shapes and order. Common fixes: every rank participates in every collective (including metrics); `drop_last=True` or padding for uneven data; no rank-dependent control flow around communication. Set a short timeout in staging, and run a 2-rank gloo test in CI that exercises the same code path (the listings here are that kind of test).

</details>

<details><summary><b>Q9 · "Pipeline parallelism: how many micro-batches?"</b></summary>

**Initial Prompt.** A 4-stage pipeline shows 40 % idle GPU time.

**L5 Answer.** "Add more stages so each is faster."

**Why L5 Crashes at Scale.** More stages make the bubble worse. Idle fraction ≈ (p-1)/(m+p-1): with p = 4 and m = 4 micro-batches it's 3/7 ≈ 43 %, close to what they see.

**L7 Principal Defense.** Raise m. With m = 16 the bubble is 3/19 ≈ 16 %, with m = 32 about 9 %, bounded by activation memory (each in-flight micro-batch holds activations, which 1F1B scheduling caps at p). Use interleaved schedules (virtual stages) to shrink the bubble further, and balance stage compute so no stage is the straggler. Pipelining exchanges only boundary activations point to point, so it's the right dimension across slow inter-node links, while TP stays inside nodes and FSDP/DP wraps both.

</details>

---

## 5. Invariants Checklist

- [ ] All-reduce = reduce-scatter + all-gather. A ring sends 2(N-1)/N·S per rank, while its latency term grows with N.
- [ ] DDP buckets gradients (25 MB by default, a 1 MiB first bucket) and overlaps all-reduce with backward. `no_sync()` skips it for accumulation.
- [ ] Mixed-precision AdamW costs 16 bytes per parameter. ZeRO-1/2/3 cut it to 4Ψ+12Ψ/N, 2Ψ+14Ψ/N and 16Ψ/N.
- [ ] Full sharding costs 3Ψ traffic vs 2Ψ. `reshard_after_forward` trades backward all-gathers for memory.
- [ ] Sharding covers model state, not activations. Combine with checkpointing, TP or sequence parallelism.
- [ ] TP all-reduces activations on the critical path, so keep it inside the fastest link domain.
- [ ] Every rank must issue the same collectives in the same order, or the job hangs.

---

## 6. References

- S. Rajbhandari, J. Rasley, O. Ruwase, Y. He, "ZeRO: Memory Optimizations Toward Training Trillion Parameter Models", SC 2020 — https://arxiv.org/abs/1910.02054
- S. Li et al., "PyTorch Distributed: Experiences on Accelerating Data Parallel Training", VLDB 2020 — https://arxiv.org/abs/2006.15704
- Y. Zhao et al., "PyTorch FSDP: Experiences on Scaling Fully Sharded Data Parallel", VLDB 2023 — https://arxiv.org/abs/2304.11277
- M. Shoeybi et al., "Megatron-LM: Training Multi-Billion Parameter Language Models Using Model Parallelism", 2019 — https://arxiv.org/abs/1909.08053
- D. Narayanan et al., "Efficient Large-Scale Language Model Training on GPU Clusters Using Megatron-LM", SC 2021 — https://arxiv.org/abs/2104.04473
- P. Patarasuk, X. Yuan, "Bandwidth optimal all-reduce algorithms for clusters of workstations", JPDC 2009, DOI 10.1016/j.jpdc.2008.09.002
- PyTorch `nn/parallel/distributed.py` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/torch/nn/parallel/distributed.py
- PyTorch `distributed/fsdp/_fully_shard/_fully_shard.py` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/torch/distributed/fsdp/_fully_shard/_fully_shard.py
- PyTorch docs: DistributedDataParallel notes — https://docs.pytorch.org/docs/stable/notes/ddp.html
- PyTorch docs: FSDP2 `fully_shard` — https://docs.pytorch.org/docs/stable/distributed.fsdp.fully_shard.html
- PyTorch docs: DeviceMesh / DTensor — https://docs.pytorch.org/docs/stable/distributed.tensor.html
- NVIDIA nccl-tests (bus bandwidth definition) — https://github.com/NVIDIA/nccl-tests/blob/master/doc/PERFORMANCE.md
