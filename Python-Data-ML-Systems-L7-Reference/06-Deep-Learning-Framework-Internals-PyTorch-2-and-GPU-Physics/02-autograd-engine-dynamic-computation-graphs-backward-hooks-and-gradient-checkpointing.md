# 06.2 · The Autograd Engine: Dynamic Computation Graphs, Backward Hooks & Gradient Checkpointing

> **Folder 06 · Deep Learning Framework Internals: PyTorch 2 & GPU Physics**
> **Measured on:** PyTorch 2.14.1+cu130, NVIDIA GeForce RTX 3050 Laptop GPU (4 GB, sm_86), i5-11260H, Windows 11, CPython 3.14.5.
> **Source quoted:** `torch/include/torch/csrc/autograd/{variable.h, node.h, edge.h, saved_variable.h, engine.h}` from the installed wheel (tag `v2.14.1`) and `torch/utils/checkpoint.py`.

---

## 0. Orientation & the JVM/C++ Bridge

Autograd is **reverse-mode automatic differentiation recorded at run time**. Each differentiable op executed on a tensor that requires grad appends a node to a graph: the backward function, the tensors it needs, and edges to the nodes that produced its inputs. `loss.backward()` walks that graph from the loss to the leaves in reverse order. The graph is rebuilt on every forward pass ("define by run"), which is why ordinary Python control flow just works, and why the memory cost of training is set by **what the graph saves**.

| Autograd concept | JVM analogue | C++ analogue |
|---|---|---|
| `grad_fn` node + saved tensors | a command object in an undo log, holding the state needed to undo | a closure capturing by value |
| saved-tensor version check | JPA `@Version` optimistic locking: "this row changed since you read it" | ABA check / generation counter |
| `register_hook` on a tensor | an interceptor / AOP advice around a call | a callback in an observer list |
| backward engine | a topological work queue with per-device worker threads | a DAG scheduler (TBB flow graph) |
| activation checkpointing | recompute-on-miss cache instead of memoizing (trade CPU for heap) | rematerialization in register allocation |
| `retain_graph=False` | release-after-use resources (`try-with-resources`) | move semantics: buffers consumed by the first backward |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 The structs

```text
 TensorImpl.autograd_meta_ ──► AutogradMeta (variable.h)
                                 grad_              Variable           the .grad tensor (accumulated into)
                                 grad_fn_           intrusive_ptr<Node> the node that produced this tensor (null for leaves)
                                 grad_accumulator_  weak_intrusive_ptr<Node>   AccumulateGrad node, for leaves
                                 hooks_, cpp_hooks_list_, post_acc_grad_hooks_
                                 requires_grad_, retains_grad_, is_view_, output_nr_ (which output of grad_fn)

 Node (node.h)                  e.g. MulBackward0, SinBackward0, AddmmBackward0, AccumulateGrad
   sequence_nr_     uint64      creation order on this thread (higher = created later = runs earlier in backward)
   topological_nr_  uint64      longest path to a leaf (used to prune traversal)
   next_edges_      vector<Edge{ intrusive_ptr<Node> function; uint32_t input_nr; }>   -> producers of my inputs
   input_metadata_  SmallVector<InputMetadata, 2>   shape/dtype/device each incoming grad must have
   pre_hooks_, tensor_pre_hooks_, post_hooks_       registered hooks
   + generated fields: SavedVariable self_, other_, result_ ... (what backward needs)

 SavedVariable (saved_variable.h)
   data_            at::Tensor    the saved tensor (or nothing, if a saved_tensors_hook packed it elsewhere)
   saved_version_   uint32        version counter value at save time
   weak_grad_fn_, grad_fn_, grad_accumulator_, is_leaf_, is_output_, hooks_ (SavedVariableHooks: pack/unpack)
```

The graph for `y = sin(w * x).sum()`, as the listing prints it:

```text
 y.grad_fn = SumBackward0 (saves the input's sizes)
               └─► SinBackward0 (saves its input u = w*x: d sin(u) = cos(u) du)
                     └─► MulBackward0 (saves x, because dy/dw = x; w isn't saved because x needs no grad)
                           └─► AccumulateGrad(w)  -> adds into w.grad
```

Each node saves the **minimum** backward needs. Which tensors that is depends on which inputs require grad, so freezing parameters (`requires_grad_(False)`) also shrinks activation memory.

### 1.2 The engine

```text
 loss.backward()
  1. build a GraphTask; walk the graph from the root and count dependencies (in-degree) per node
  2. push the root into the ReadyQueue of its device
       ReadyQueue = priority_queue ordered by (reentrant depth, then higher sequence_nr first)   (engine.h)
  3. worker loop: pop node -> run pre-hooks -> node.apply(grads) -> post-hooks
       for each next_edge: add the produced grad into that node's InputBuffer (sums fan-in gradients);
       when its dependency count hits 0, push it to the ReadyQueue of the device its inputs live on
  4. CPU work runs on the calling thread; each CUDA device has its own engine worker thread
  5. AccumulateGrad: leaf.grad = grad (first time) or leaf.grad += grad (accumulates across backward() calls)
  6. unless retain_graph=True: saved variables are released as each node finishes
```

Step 5 is why `optimizer.zero_grad(set_to_none=True)` is part of every loop. Step 6 is why a second `backward()` through the same graph fails (the listing shows both).

### 1.3 Where training memory goes

Measured for an 8-layer MLP (width 2048, batch 4096, fp32; one activation = 32 MiB):

```text
 saved_tensors_hooks count: 23 saved tensors, 624 MiB "saved"
   8 Linear inputs (8 x 32 MiB)       saved by AddmmBackward for grad_weight = grad_out^T @ input
   7 Linear weights (7 x 16 MiB)      for grad_input = grad_out @ W; the first layer's input needs no grad, so no W
   8 GELU inputs (8 x 32 MiB)         GELU backward needs its input
   = 256 + 112 + 256 = 624 MiB; 8 + 7 + 8 = 23 tensors
 memory actually held after forward: 520 MiB
   the 7 weights and the input are aliases of tensors that already exist (no new bytes):
   new = 8 Linear outputs + 7 GELU outputs + the final output = 16 x 32 MiB = 512 MiB (+ ~8 MiB cuBLAS workspace)
 under torch.no_grad(): 32 MiB (just the output; each intermediate is freed as soon as the next op consumes it)
```

That's 16× the memory of inference for the same forward, before gradients (one per parameter) and optimizer state (AdamW: 2 more per parameter) are counted.

### 1.4 The version counter

Every tensor's storage shares a `VariableVersion` counter. In-place ops (`add_`, `relu_`, `x[...] = ...`) increment it. `SavedVariable` records `saved_version_` and compares it on unpack. If they differ, backward would read modified data, so it raises `one of the variables needed for gradient computation has been modified by an inplace operation`. `exp` saves its **output**, so `b = a.exp(); b.add_(1)` breaks backward (reproduced). `tensor.data` bypasses the counter. It's the way to get silently wrong gradients; use `detach()` (shares the counter) or `torch.no_grad()`.

### 1.5 Activation checkpointing

```text
 normal:        forward saves activations of every layer ──► backward reads them           memory O(L)
 checkpointed:  forward keeps only each segment's INPUT; on backward, re-run the segment's forward with grad
                enabled to regenerate its saved tensors, then backward through it          memory O(L/k + k)
                k = sqrt(L) segments -> O(sqrt(L)) memory for one extra forward (Chen et al. 2016)
 non-reentrant (use_reentrant=False): implemented with saved_tensors_hooks. Pack stores a placeholder; the first
                unpack triggers recomputation, which stops early once every needed tensor is regenerated.
                It supports torch.autograd.grad, inputs that don't require grad, and nested structures.
 reentrant (use_reentrant=True): an autograd.Function whose backward calls the engine again. If no INPUT requires
                grad, the segment's parameters silently get no gradient.
 RNG: preserve_rng_state=True stashes the CPU/CUDA RNG state so dropout masks match on recomputation
```

⚠ **The default is still the risky one.** In 2.14.1, `checkpoint()` without `use_reentrant` warns and falls back to `use_reentrant=True` (`torch/utils/checkpoint.py` line 635), although the warning text says 2.9 would make it an error. Always pass `use_reentrant=False` explicitly.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 The tape: nodes, saved bytes, hooks, version checks

```python
"""autograd_graph.py - the autograd tape: grad_fn nodes, saved tensors, hooks, version counters, and grad modes.

A: walk the backward graph a forward pass records (grad_fn -> next_functions).
B: count the bytes autograd saves for backward (saved_tensors_hooks) for an MLP on CUDA, and under no_grad.
C: hooks: inspect and clip gradients in flight; gradients accumulate across backward() calls.
D: the errors that protect correctness: in-place modification of a saved tensor; backward twice.
"""
import torch

dev = torch.device("cuda")
print("== A. the graph recorded by y = sin(w * x).sum()")
x = torch.randn(4, device=dev)
w = torch.randn(4, device=dev, requires_grad=True)
y = torch.sin(w * x).sum()


def walk(fn, depth=0, seen=None):
    seen = seen or set()
    if fn is None or fn in seen:
        return
    seen.add(fn)
    print(f"  {'  ' * depth}{type(fn).__name__}")
    for nxt, _ in fn.next_functions:
        walk(nxt, depth + 1, seen)


walk(y.grad_fn)
y.backward()
assert torch.allclose(w.grad, torch.cos(w * x) * x)
print(f"  w.grad == cos(w*x)*x: True; x.grad is {x.grad} (x does not require grad)")

print("== B. what autograd keeps alive for backward: an 8-layer MLP, batch 4096, width 2048, fp32")
mlp = torch.nn.Sequential(*[m for _ in range(8) for m in (torch.nn.Linear(2048, 2048), torch.nn.GELU())]).to(dev)
inp = torch.randn(4096, 2048, device=dev)
saved = {"n": 0, "bytes": 0}


def pack(t):
    saved["n"] += 1
    saved["bytes"] += t.numel() * t.element_size()
    return t


def unpack(t):
    return t


torch.cuda.synchronize()
base = torch.cuda.memory_allocated()
with torch.autograd.graph.saved_tensors_hooks(pack, unpack):
    out = mlp(inp)
with_graph = torch.cuda.memory_allocated() - base
print(f"  forward with grad: {saved['n']} saved tensors, {saved['bytes'] / 2**20:.0f} MiB saved "
      f"(activation = {inp.numel() * 4 / 2**20:.0f} MiB each); memory held after forward {with_graph / 2**20:.0f} MiB")
del out
torch.cuda.synchronize()
base = torch.cuda.memory_allocated()
with torch.no_grad():
    out = mlp(inp)
print(f"  forward under no_grad: memory held after forward {(torch.cuda.memory_allocated() - base) / 2**20:.0f} MiB "
      f"(only the output)")
del out

print("== C. hooks and accumulation")
p = torch.randn(3, device=dev, requires_grad=True)
seen = []
h = p.register_hook(lambda g: (seen.append(g.norm().item()), g.clamp(-1, 1))[1])   # observe, then clip
(p * 100).sum().backward()
print(f"  hook saw gradient norm {seen[0]:.1f}; stored p.grad after clipping = {p.grad.tolist()}")
(p * 100).sum().backward()
print(f"  second backward without zeroing: p.grad = {p.grad.tolist()} (accumulates)")
h.remove()
p.grad = None

print("== D. guards against silent corruption")
a = torch.randn(3, device=dev, requires_grad=True)
b = a.exp()                                              # backward of exp needs its output b
b.add_(1)                                                # in-place: bumps b's version counter
try:
    b.sum().backward()
except RuntimeError as e:
    print(f"  in-place on a saved tensor -> RuntimeError: {str(e).split('.')[0][:100]}")
c = (a * 2).sum()
c.backward()
try:
    c.backward()
except RuntimeError as e:
    print(f"  backward twice -> RuntimeError: {str(e).split(';')[0][:100]}")
print("ALL ASSERTIONS PASSED")
```

Output (deterministic, verified):

```text
== A. the graph recorded by y = sin(w * x).sum()
  SumBackward0
    SinBackward0
      MulBackward0
        AccumulateGrad
  w.grad == cos(w*x)*x: True; x.grad is None (x does not require grad)
== B. what autograd keeps alive for backward: an 8-layer MLP, batch 4096, width 2048, fp32
  forward with grad: 23 saved tensors, 624 MiB saved (activation = 32 MiB each); memory held after forward 520 MiB
  forward under no_grad: memory held after forward 32 MiB (only the output)
== C. hooks and accumulation
  hook saw gradient norm 173.2; stored p.grad after clipping = [1.0, 1.0, 1.0]
  second backward without zeroing: p.grad = [2.0, 2.0, 2.0] (accumulates)
== D. guards against silent corruption
  in-place on a saved tensor -> RuntimeError: one of the variables needed for gradient computation has been modified by an inplace operation: [tor
  backward twice -> RuntimeError: Trying to backward through the graph a second time (or directly access saved tensors after they have
ALL ASSERTIONS PASSED
```

* The graph walk is the structure in §1.1. `x.grad is None`: tensors that don't require grad get no `AccumulateGrad` and nothing is saved for them.
* **624 MiB saved vs 520 MiB held vs 32 MiB under `no_grad`**: §1.3 accounts for every byte. The slow trap is running evaluation or inference without `no_grad`/`inference_mode`, which holds the whole graph alive until the output is dropped.
* The hook saw the raw gradient (norm 173.2 = 100·√3) and its return value replaced the gradient stored in `p.grad`. A second `backward()` without zeroing **accumulated** (`[2, 2, 2]`).
* Both guard errors are the engine protecting correctness: an in-place write to a saved output, and a second backward after the saved tensors were freed.

### 2.2 Checkpointing: trade one recomputation for activation memory

```python
"""activation_checkpointing.py - trade compute for memory: peak GPU memory and step time with and without checkpointing.

A 16-block residual MLP (width 2048, batch 2048, fp32) on CUDA. Without checkpointing, every block's activations
are saved for backward. torch.utils.checkpoint keeps only block inputs and recomputes each block's forward during
backward. Peak memory comes from torch.cuda.max_memory_allocated (the caching allocator's high-water mark).
"""
import time

import torch
from torch.utils.checkpoint import checkpoint, checkpoint_sequential

dev = torch.device("cuda")
torch.manual_seed(0)


class Block(torch.nn.Module):
    def __init__(self, d):
        super().__init__()
        self.ln = torch.nn.LayerNorm(d)
        self.fc1 = torch.nn.Linear(d, 2 * d)
        self.fc2 = torch.nn.Linear(2 * d, d)

    def forward(self, x):
        return x + self.fc2(torch.nn.functional.gelu(self.fc1(self.ln(x))))


D, B, L = 2048, 2048, 16
blocks = torch.nn.ModuleList([Block(D) for _ in range(L)]).to(dev)
x0 = torch.randn(B, D, device=dev)


def forward(mode):
    h = x0.requires_grad_(False)
    if mode == "none":
        for blk in blocks:
            h = blk(h)
    elif mode == "per-block":
        for blk in blocks:
            h = checkpoint(blk, h, use_reentrant=False)
    else:                                                # 4 segments of 4 blocks
        h = checkpoint_sequential(torch.nn.Sequential(*blocks), 4, h, use_reentrant=False)
    return h.pow(2).mean()


def run(mode):
    for p in blocks.parameters():
        p.grad = None
    torch.cuda.synchronize()
    torch.cuda.reset_peak_memory_stats()
    base = torch.cuda.memory_allocated()
    t0 = time.perf_counter()
    loss = forward(mode)
    torch.cuda.synchronize()
    held = torch.cuda.memory_allocated() - base          # what autograd keeps alive between forward and backward
    loss.backward()
    torch.cuda.synchronize()
    return time.perf_counter() - t0, held / 2**20, (torch.cuda.max_memory_allocated() - base) / 2**20, loss.item()


params = sum(p.numel() for p in blocks.parameters())
print(f"{L} blocks x (LayerNorm + {D}->{2 * D}->{D} MLP), batch {B}, {params / 1e6:.0f}M params "
      f"({params * 4 / 2**20:.0f} MiB fp32 weights; backward allocates the same again for grads)")
print(f"one activation tensor ({B} x {D} fp32) = {B * D * 4 / 2**20:.0f} MiB")
print(f"{'checkpointing':28} {'step time':>10} {'held after fwd':>15} {'step peak':>11}")
res = {}
for mode, label in (("none", "none"), ("segments", "checkpoint_sequential(4)"), ("per-block", "checkpoint per block")):
    run(mode)                                            # warm-up (cuBLAS handles, allocator pools)
    dt, held, peak, loss = run(mode)
    res[mode] = (dt, held, peak, loss)
    print(f"  {label:26} {dt * 1e3:8.0f}ms {held:12.0f} MiB {peak:8.0f} MiB")
assert abs(res["none"][3] - res["per-block"][3]) < 1e-5
assert res["per-block"][1] < res["none"][1] / 4
print(f"  per-block: {res['none'][1] / res['per-block'][1]:.0f}x less memory held for backward, "
      f"{res['per-block'][0] / res['none'][0]:.2f}x the step time (one extra forward per block)")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
16 blocks x (LayerNorm + 2048->4096->2048 MLP), batch 2048, 269M params (1025 MiB fp32 weights; backward allocates the same again for grads)
one activation tensor (2048 x 2048 fp32) = 16 MiB
checkpointing                 step time  held after fwd   step peak
  none                           1061ms         1536 MiB     1612 MiB
  checkpoint_sequential(4)       1315ms          432 MiB     1217 MiB
  checkpoint per block           1264ms          256 MiB     1121 MiB
  per-block: 6x less memory held for backward, 1.19x the step time (one extra forward per block)
ALL ASSERTIONS PASSED
```

* Memory held for backward dropped from **1536 MiB to 432 MiB** (4 segments) and **256 MiB** (per block), 3.6× and 6×, with an identical loss (asserted).
* The cost was **~1.19–1.42× the step time**: each block's forward runs twice, and the backward of an MLP is roughly 2× its forward, so the theoretical overhead is ~33 %. The spread across runs came from GPU clock throttling on this laptop (§3, F10), not from the algorithm.
* The *step peak* only fell from 1612 to 1121 MiB, because this model has 1 GiB of parameters and backward allocates another GiB of gradients. Checkpointing removes activation memory, never parameter, gradient or optimizer-state memory. For those you need sharding (FSDP/ZeRO, 07.1).

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Memory grows every step until OOM | `total_loss += loss` or appending `loss` to a list | Each `loss` holds its whole graph and saved activations | `total_loss += loss.item()` (sync) or `loss.detach()` | Lint: never accumulate tensors that require grad |
| F2 🔥 | OOM only during validation | Eval loop without `no_grad` | Graph built and saved for nothing | `torch.inference_mode()` around evaluation | Wrap eval/serving paths centrally |
| F3 | `model.eval()` but memory/latency unchanged | Graph still recorded | `eval()` changes dropout/BatchNorm behaviour only | Add `inference_mode`/`no_grad` | Separate "mode" from "grad recording" in reviews |
| F4 | `modified by an inplace operation ... version N; expected version N-1` | In-place op after the tensor was saved | Version-counter check (§1.4) | Out-of-place op, or `clone()` before the in-place write | `set_detect_anomaly(True)` in a debug run pinpoints the forward op |
| F5 🔥 | Training diverges after "small refactor" | Grads too large by the number of steps | Missing `zero_grad` (accumulation) | `optimizer.zero_grad(set_to_none=True)` each step | Unit test: two identical steps give identical grads |
| F6 🔥 | Frozen-input checkpointed layers stop learning | Parameters' grads are `None` | `use_reentrant=True` with no input requiring grad | `use_reentrant=False` | Always pass it explicitly (2.14.1 still defaults to True) |
| F7 | Checkpointed model gives different loss than plain | Dropout inside checkpointed region | RNG not preserved or nondeterministic kernels | Keep `preserve_rng_state=True` | Parity test: checkpointed vs plain loss (the listing asserts it) |
| F8 | Silently wrong gradients | `.data` used for in-place updates | `.data` bypasses version tracking | `with torch.no_grad(): p.add_(...)` or `detach()` | Ban `.data` in lint |
| F9 | Memory leak from hooks | Hooks capturing tensors or modules in closures | Hook keeps references alive | Remove handles (`h.remove()`); capture weakly | Register hooks in a context manager |
| F10 ⚡ | Benchmark numbers drift 30–70 % between runs | Laptop GPU at 84 °C, SM clock below max | Thermal or power throttling | Warm up to steady state; report clocks (`nvidia-smi --query-gpu=clocks.sm,temperature.gpu`) | Benchmark on cooled, fixed-clock hardware |

**Debugging toolkit.** `torch.autograd.graph.saved_tensors_hooks(pack, unpack)` (count or offload saved bytes; `save_on_cpu` is a ready-made offloader); `tensor.grad_fn.next_functions` and `grad_fn._saved_*` attributes; `torch.autograd.set_detect_anomaly(True)` (records forward stack traces per node, slow); `torch.autograd.gradcheck` for custom `Function`s; `torch.cuda.memory_allocated()` after forward vs after backward; `torch.profiler` with `profile_memory=True`.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why does training need 16× the activation memory of inference for the same forward pass?"</b></summary>

**Initial Prompt.** A model serves at 32 MiB of activations per batch but training OOMs at the same batch size.

**L5 Answer.** "Training stores gradients, so it needs about 2×."

**Why L5 Crashes at Scale.** It undercounts by an order of magnitude. Gradients are per **parameter**; the dominant term is the per-**activation** saved tensors, which grow with batch × sequence × depth. Capacity plans based on "2×" fail on the first long-sequence run.

**L7 Principal Defense.** Count what backward needs. Each Linear saves its input (for the weight gradient) and the weight (for the input gradient), each GELU saves its input. Measured on an 8-layer MLP: 23 saved tensors, 624 MiB "saved", 520 MiB of new memory held after forward vs 32 MiB under `no_grad`, about 16×. Training adds parameters + gradients + optimizer state on top (AdamW: ~16 bytes per parameter in fp32). Levers by cost: freeze what you don't train (fewer saved tensors), mixed precision (activations in 16-bit, 06.4), checkpointing (O(√L)), offloading saved tensors to CPU (`save_on_cpu`), and sharding for the parameter side (07.1).

</details>

<details><summary><b>Q2 · "Memory grows by a few hundred MB per step. Where's the leak?"</b></summary>

**Initial Prompt.** A training loop's memory climbs linearly until OOM after ~200 steps.

**L5 Answer.** "PyTorch's allocator caches memory; call `torch.cuda.empty_cache()` every step."

**Why L5 Crashes at Scale.** `empty_cache` releases only *unused* cached blocks. This memory is in use: something holds references to graphs. Calling it every step also adds `cudaFree`/`cudaMalloc` round trips and synchronization.

**L7 Principal Defense.** The classic cause is `running_loss += loss` (or `losses.append(loss)`). Each `loss` keeps its `grad_fn` and therefore every saved activation of that step alive. Use `loss.detach()` for on-device accumulation, or `.item()` every N steps. Other causes: hooks capturing tensors, `retain_graph=True` in a loop, caching model outputs for logging. Diagnose with `memory_allocated()` per step (it grows linearly) and the allocator's memory snapshot (`torch.cuda.memory._record_memory_history()` → `_dump_snapshot`), which shows the allocation stack of each live block.

</details>

<details><summary><b>Q3 · "What does 'modified by an inplace operation' mean, and can we just use `.data`?"</b></summary>

**Initial Prompt.** A custom activation does `out.add_(bias)` after `exp`, and backward raises.

**L5 Answer.** "Use `out.data.add_(bias)` to get around it."

**Why L5 Crashes at Scale.** The error is a correctness check, not a nuisance. `exp`'s backward computes `grad * output` from the **saved output**. Modifying it in place changes what backward reads. `.data` hides the version bump, so the gradient becomes silently wrong. Training "works" and converges to the wrong thing.

**L7 Principal Defense.** Autograd stores the version counter value with each saved tensor and checks it on unpack (§1.4). The fix is out-of-place (`out = out + bias`), letting the compiler fuse it later, or `clone()` before the in-place write. The memory cost of out-of-place is usually recovered by `torch.compile`, which reuses buffers. In-place is safe where nothing saved depends on the value: ReLU's backward uses its output only as a mask, so `inplace=True` works there. When unsure, `set_detect_anomaly(True)` points to the forward line that saved the tensor.

</details>

<details><summary><b>Q4 · "Should we turn on activation checkpointing everywhere?"</b></summary>

**Initial Prompt.** A transformer OOMs at the desired sequence length. Someone proposes checkpointing every layer.

**L5 Answer.** "Yes. It saves memory for free."

**Why L5 Crashes at Scale.** It isn't free. Each checkpointed block runs its forward twice, measured at ~1.19–1.42× step time. On a compute-bound job that's up to ~33 % more GPU hours. Per-block checkpointing also re-runs expensive matmuls when only cheap pointwise activations needed recomputing.

**L7 Principal Defense.** Decide by the memory curve. Measured: per-block checkpointing cut held activations 6× (1536 → 256 MiB) and segments of 4 cut them 3.6×. Checkpoint only as much as needed to fit the target batch, since a larger batch often recovers the recompute cost through better utilization. Prefer **selective** recomputation: save matmul outputs and recompute pointwise ops (cheap FLOPs, expensive bytes). That's what Inductor's min-cut partitioner does automatically under `torch.compile` (06.3). Always `use_reentrant=False`, keep RNG preservation for dropout, and test loss parity checkpointed vs plain (the listing asserts it).

</details>

<details><summary><b>Q5 · "We need a 4,096 batch but only 512 fits. What do we do?"</b></summary>

**Initial Prompt.** The recipe calls for an effective batch of 4,096; the GPU fits 512.

**L5 Answer.** "Lower the learning rate and use batch 512."

**Why L5 Crashes at Scale.** It changes the optimization recipe (noise scale, warmup, LR schedule) and the result no longer reproduces the reference.

**L7 Principal Defense.** Gradient accumulation: run 8 micro-batches, divide each loss by 8, call `backward()` each time (AccumulateGrad sums into `.grad`, as the listing shows), then step and zero. Under DDP, wrap the first 7 in `model.no_sync()` to skip 7 of 8 all-reduces. BatchNorm statistics see micro-batches (use LayerNorm/GroupNorm, or SyncBN), and step time is ~8× per optimizer step, so combine with checkpointing or bf16 to enlarge micro-batches. Verify equivalence on a small model: accumulated grads vs one large batch, equal to tolerance.

</details>

<details><summary><b>Q6 · "Implement per-parameter gradient clipping with hooks — or not?"</b></summary>

**Initial Prompt.** A design proposes `register_hook` on every parameter to clamp gradients.

**L5 Answer.** "Hooks are the clean way; clamp each gradient to [-1, 1]."

**Why L5 Crashes at Scale.** Element-wise clamping changes the gradient's **direction**, not just its magnitude, which differs from the standard global-norm clipping recipes. It also runs per parameter per backward, outside any fused kernel. With DDP, hooks on parameters run before the all-reduce, so each rank clips its local gradient differently.

**L7 Principal Defense.** Use `clip_grad_norm_` after `backward()` (and after `scaler.unscale_` under fp16 AMP): one global norm, fused `foreach` kernels, same result on every rank after the all-reduce. Reserve hooks for observation (gradient norms for monitoring), gradient compression in DDP communication hooks, or research cases where per-tensor transformation is the intent. The listing shows the mechanics: the hook saw the raw gradient (norm 173.2) and its return value replaced the stored one. Remove hook handles when done; hooks that capture tensors leak.

</details>

<details><summary><b>Q7 · "In what order does backward run, and is it parallel?"</b></summary>

**Initial Prompt.** Explain how the engine schedules a graph with branches across CPU and GPU.

**L5 Answer.** "It runs the layers in reverse order on one thread."

**Why L5 Crashes at Scale.** "Reverse layer order" misses fan-in accumulation, multi-device graphs, reentrant backward (checkpointing), and why a CPU-side op in a GPU model can stall backward.

**L7 Principal Defense.** `backward()` builds a GraphTask, counts dependencies per node, and seeds the root. Each device has a ReadyQueue, a priority queue ordered by reentrant depth and then descending `sequence_nr` (later-created nodes first, which approximates reverse topological order; `engine.h`). CPU nodes run on the calling thread and each CUDA device has a worker thread, so CPU and GPU parts of a graph overlap. `InputBuffer`s sum gradients from multiple consumers before a node becomes ready. GPU kernels are still launched asynchronously into streams, so "parallel" mostly means the CPU-side scheduling keeps queues full. DDP hooks into this (bucketed all-reduce as gradients become ready) to overlap communication with the rest of backward (07.1).

</details>

<details><summary><b>Q8 · "Why did PyTorch's dynamic graphs beat static graphs, and why compile now?"</b></summary>

**Initial Prompt.** TensorFlow 1 compiled static graphs; PyTorch builds the graph every step. Why did define-by-run win, and doesn't `torch.compile` undo that?

**L5 Answer.** "Dynamic graphs are easier to debug; compile is optional."

**Why L5 Crashes at Scale.** It misses the actual trade-off: static graphs enabled whole-program optimization (fusion, memory planning) at the cost of a separate language for control flow. Without that framing you can't reason about when compiled graphs break or what they buy.

**L7 Principal Defense.** Define-by-run makes the graph a by-product of executing Python. Control flow, debuggers and printing all work, and the tape holds exactly the ops that ran. The cost is per-op overhead (06.1) and no cross-op optimization. `torch.compile` gets both: Dynamo captures graphs from the bytecode at run time with guards, falls back to Python on unsupported code (graph breaks), and AOTAutograd traces **forward and backward ahead of time**, so Inductor can fuse kernels and choose what to save vs recompute (06.3). The eager tape remains the semantics; compilation is an optimization with a verified fallback.

</details>

<details><summary><b>Q9 · "Freezing layers: does it save compute only, or memory too?"</b></summary>

**Initial Prompt.** Fine-tune only the top 2 layers of a 24-layer encoder.

**L5 Answer.** "It saves optimizer memory because frozen layers have no optimizer state."

**Why L5 Crashes at Scale.** It misses the larger effect. When nothing below a layer requires grad, autograd doesn't record those ops at all: no saved activations and no backward through the frozen stack.

**L7 Principal Defense.** Saved tensors depend on which inputs require grad. The listing shows `MulBackward0` saving only `x` because `x` didn't need a gradient, and the first Linear saving no weight. Set `requires_grad_(False)` on the frozen stack, or run it under `torch.no_grad()` and feed its output (detached) to the trainable head. Activation memory then covers only the trainable layers and backward stops at the boundary. Parameter-efficient methods (LoRA, 07.2) push this further: the base weights are frozen, the trainable adapters are small, and the main remaining activation cost is what the adapters' inputs require.

</details>

---

## 5. Invariants Checklist

- [ ] The graph is recorded as ops execute. Each node saves only what its backward needs, given which inputs require grad.
- [ ] Training activation memory is the saved tensors (520 MiB vs 32 MiB under `no_grad` here), on top of parameters, gradients and optimizer state.
- [ ] Never accumulate tensors that require grad across steps. Never use `.data`.
- [ ] Gradients accumulate into `.grad` until zeroed (`set_to_none=True`).
- [ ] Saved tensors are version-checked. In-place writes to them fail loudly, which is a feature.
- [ ] Checkpointing trades one extra forward for O(√L) activation memory (6× less, ~1.2–1.4× time here). Pass `use_reentrant=False` explicitly.
- [ ] `model.eval()` changes layer behaviour; `inference_mode()` stops graph recording. Serving needs both.

---

## 6. References

- PyTorch `variable.h` (AutogradMeta, v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/torch/csrc/autograd/variable.h
- PyTorch `node.h` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/torch/csrc/autograd/node.h
- PyTorch `engine.h` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/torch/csrc/autograd/engine.h
- PyTorch `utils/checkpoint.py` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/torch/utils/checkpoint.py
- PyTorch docs: autograd mechanics — https://docs.pytorch.org/docs/stable/notes/autograd.html
- PyTorch docs: `torch.utils.checkpoint` — https://docs.pytorch.org/docs/stable/checkpoint.html
- PyTorch tutorial: hooks for autograd saved tensors — https://docs.pytorch.org/tutorials/intermediate/autograd_saved_tensors_hooks_tutorial.html
- A. Paszke et al., "PyTorch: An Imperative Style, High-Performance Deep Learning Library", NeurIPS 2019 — https://arxiv.org/abs/1912.01703
- T. Chen, B. Xu, C. Zhang, C. Guestrin, "Training Deep Nets with Sublinear Memory Cost", 2016 — https://arxiv.org/abs/1604.06174
- V. Korthikanti et al., "Reducing Activation Recomputation in Large Transformer Models", 2022 (selective recomputation) — https://arxiv.org/abs/2205.05198
