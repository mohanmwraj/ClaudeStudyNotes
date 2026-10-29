# 06.3 · `torch.compile`: Dynamo Bytecode Capture, AOTAutograd, Inductor & Triton Kernels

> **Folder 06 · Deep Learning Framework Internals: PyTorch 2 & GPU Physics**
> **Measured on:** PyTorch 2.14.1+cu130 with TorchInductor generating Triton kernels through **triton-windows 3.9.0.post30** (⚠ a community-maintained Windows build of OpenAI Triton; it links its launcher with the bundled TinyCC), NVIDIA GeForce RTX 3050 Laptop GPU (sm_86, 16 SMs), i5-11260H, Windows 11, CPython 3.14.5. Inductor and Triton caches are wiped before every run, so compile times are cold.
> **Source quoted:** `torch/_dynamo/config.py`, `torch/_inductor/config.py`, `torch/_functorch/partitioners.py` in the installed wheel (tag `v2.14.1`).

---

## 0. Orientation & the JVM/C++ Bridge

`torch.compile` is a JIT for PyTorch programs, built in four layers. **Dynamo** intercepts Python frame evaluation (PEP 523), symbolically executes the bytecode, and extracts straight-line tensor computation into an **FX graph** guarded by assumptions about the inputs. **AOTAutograd** traces that graph's forward and backward to ATen ops ahead of time and decides what to save. **Inductor** fuses the ATen graph into loops and emits **Triton** kernels (GPU) or C++/OpenMP (CPU). Anything Dynamo can't trace runs in normal Python (a graph break). If you know HotSpot, you already know the shape of this.

| torch.compile | HotSpot / Graal analogue | C++ analogue |
|---|---|---|
| Dynamo frame hook (PEP 523) | the interpreter handing a hot method to the JIT | LD_PRELOAD-style interposition on the interpreter loop |
| guards on dtype/shape/constants | speculative assumptions + uncommon traps (deoptimization) | PGO with runtime checks |
| recompile on guard failure, `recompile_limit = 8` | deopt + reprofile; `PerMethodRecompilationCutoff` | — |
| graph break | a call the JIT won't inline; the interpreter runs it | an opaque external call between optimized regions |
| FX graph | Graal IR / C2 sea of nodes | LLVM IR (SSA) |
| AOTAutograd partitioner | escape analysis + rematerialization in the register allocator | compiler rematerialization |
| Inductor + Triton | the C2 backend's codegen | a kernel compiler (Halide, XLA, TVM) |
| `mode="reduce-overhead"` | — | CUDA Graphs (one launch per captured sequence) |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 Dynamo: capturing graphs from bytecode

```text
 PEP 523: CPython calls interp->eval_frame(tstate, frame, throwflag) for every Python frame.
 torch.compile(fn) installs Dynamo's callback for fn's code object:

 call fn(x, k) ──► Dynamo callback
                    ├─ cache lookup on this code object: for each entry, run its guards (a C++ guard tree)
                    │     tensor x: dtype, device, requires_grad, sizes (static or symbolic), strides
                    │     python k: type and value (k == 2), globals and attributes read by the code
                    ├─ hit  → run the cached transformed bytecode: call the compiled graph, rebuild Python state
                    └─ miss → InstructionTranslator symbolically executes the bytecode on VariableTrackers:
                              torch ops on TensorVariables → FX nodes (FakeTensors propagate shapes, no real data)
                              unsupported (print, .item() without capture_scalar_outputs, C extensions, I/O)
                                → graph break: compile the graph so far, run the offending bytecode in Python,
                                  resume tracing in a generated function "torch_dynamo_resume_in_<fn>_at_<line>"
                              → emit new bytecode + guards, store a cache entry, run it
```

The listing's graph-break case produced **3 graphs and 2 breaks** from one function (`print` → "Failed to trace builtin operator"; `.item()` → "Unsupported Tensor.item() call with capture_scalar_outputs=False"). `fullgraph=True` turns the first break into an exception, which is what you want in CI.

### 1.2 Guards, recompiles and dynamic shapes

```text
 first call: everything specialized (static sizes, k == 2)
 a size changes  → guard fails → recompile with that dimension SYMBOLIC (automatic_dynamic_shapes = True)
                   → later sizes reuse the symbolic entry (sizes 0 and 1 stay specialized)
 dtype changes   → always a new entry (kernels are dtype-specific)
 a Python int changes → recompile; a second distinct value makes it a SymInt as well
 per code object: recompile_limit = 8 entries (config.py:121), then Dynamo stops compiling that frame and runs it
                  eagerly, with a warning in the log; accumulated_recompile_limit = 256 overall
```

Measured sequence: `float32[8], k=2` compiled; `[16]` recompiled on `size mismatch at index 0. expected 8, actual 16`; `[32]` and `[1000]` reused the now-dynamic entry; `float16` recompiled on dtype; `k=3` recompiled on `k == 2`; `k=4` reused (k became dynamic). That's 4 compiles for 8 calls. A loop whose Python scalar takes many values, or a dataloader whose shapes vary, burns through the recompile limit and silently falls back to eager.

### 1.3 AOTAutograd: forward and backward, ahead of time

```text
 FX graph (torch-level) ──► trace with FakeTensors through the dispatcher, below autograd:
   functionalize (in-place and views → pure ops) ; decompose to core ATen ; build ONE joint graph fwd + bwd
 ──► partition the joint graph:
     default partitioner: save what eager autograd would save
     min-cut rematerialization (Inductor's default): choose the set of saved tensors that minimizes bytes moved,
     recomputing cheap (pointwise) ops in the backward instead of saving their outputs
 ──► forward graph: outputs = (real outputs..., saved tensors)   backward graph: inputs = (saved..., grad_outputs)
```

The listing makes this concrete. For the pointwise chain `exp(cos(sin(w*x)))`, the default partitioner saves 3 computed tensors (`w*x`, `sin`, `exp`). The min-cut partitioner saves **1** and recomputes `w*x` and `sin` inside the backward (the extra `mul` and `sin` in its backward op list). For the MLP both save the same storage, but min-cut stores transposed views so the backward skips 4 ops. This is selective activation checkpointing (06.2), chosen by a max-flow/min-cut over byte costs instead of by hand.

### 1.4 Inductor: from ATen to fused loops

```text
 ATen graph → lowering to Inductor IR: Pointwise / Reduction / Scatter nodes over index expressions (sympy)
            → scheduler: fuse nodes with compatible iteration spaces
                vertical (producer → consumer: sin, cos, mul, add into one loop)
                horizontal (independent loops over the same range), epilogue fusion into matmul templates
            → codegen: Triton kernels for GPU (C++/OpenMP for CPU) + a Python (or C++) wrapper that allocates
              buffers (reusing dead ones) and launches kernels
 matmuls: extern calls to cuBLAS by default; Triton GEMM templates only under max_autotune on a "big GPU"
          (logged here: "Not enough SMs to use max_autotune_gemm mode", 16 SMs)
```

The kernel Inductor wrote for `sin(a) + cos(b) * c` (printed by the listing) has three `tl.load`s, five register temporaries and one `tl.store`. The intermediates `t1..t3` never touch DRAM:

```text
 eager:   K1 sin: read a, write t1 │ K2 cos: read b, write t2 │ K3 mul: read t2, c, write t3 │ K4 add: read t1, t3, write x
          4 launches, 11 tensor-sized DRAM passes
 fused:   K  : read a, b, c → registers → write x
          1 launch, 4 passes      → ideal speedup for a bandwidth-bound op = 11/4 = 2.75x
```

⚠ The brief's "reading/writing HBM 3 separate times" undercounts. Eager makes 4 kernels and 11 passes over memory, and the measured speedup (~2.5×) tracks the 2.75× traffic ratio, which shows the op is bandwidth-bound.

### 1.5 Triton in one paragraph

Triton is a Python-embedded language where one **program** processes a block (`tl.arange(0, XBLOCK)`) and the compiler handles coalescing, vectorization, shared-memory staging, tensor-core instructions and register allocation. It lowers through MLIR to LLVM, PTX and `ptxas`. Inductor writes Triton because block-level code is far easier to generate than CUDA C, and autotuning over `XBLOCK`/`num_warps` configurations is built in.

### 1.6 Modes and their costs

```text
 default            Dynamo + AOTAutograd + Inductor; guards checked per call (~µs)
 reduce-overhead    + CUDA Graphs ("cudagraph trees"): one replay per graph; needs static input addresses
                      (inputs copied into graph-owned buffers), extra memory per distinct shape
 max-autotune       + Triton GEMM/conv templates benchmarked at compile time (much longer compile)
 dynamic=True/False force symbolic or static shapes from the start
 backend="eager" / "aot_eager"   bisect: Dynamo only / Dynamo + AOTAutograd, no Inductor
 cost: the first call traced, partitioned, generated and compiled one fused kernel in ~3.4–4.9 s with cold caches;
       on-disk FX-graph and Triton caches make the next process start much faster
```

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 What Dynamo captures, when it breaks, and when it recompiles

```python
"""dynamo_graph_capture.py - what torch.compile's front end sees: FX graphs, graph breaks, guards, recompiles, AOTAutograd.

A: a custom backend receives each FX graph Dynamo captured by symbolically evaluating the Python bytecode.
B: graph breaks: print() and .item()-driven control flow split one function into several graphs; fullgraph=True refuses.
C: guards: a new shape, dtype or constant fails a guard and recompiles; automatic dynamic shapes stop the churn.
D: AOTAutograd traces forward + backward to ATen and partitions them; saved tensors become forward-graph outputs,
   and the min-cut partitioner recomputes a cheap pointwise chain in backward instead of saving it.
"""
import logging

import torch
import torch._dynamo as dynamo
from functorch.compile import make_boxed_func, min_cut_rematerialization_partition
from torch._dynamo.backends.common import aot_autograd
from torch._dynamo.testing import CompileCounter

dev = torch.device("cuda")
torch.manual_seed(0)


def ops(gm):
    return [str(n.target).replace("aten.", "").replace(".default", "") if n.op == "call_function" else n.op
            for n in gm.graph.nodes if n.op not in ("placeholder", "output")]


print("== A. the FX graph a backend receives")
graphs = []


def inspect_backend(gm, example_inputs):
    graphs.append(gm)
    return gm.forward                                    # run the captured graph as-is (no code generation)


def mlp(x, w1, w2):
    h = torch.nn.functional.gelu(x @ w1)
    return (h @ w2).relu().sum()


x = torch.randn(64, 128, device=dev)
w1 = torch.randn(128, 256, device=dev, requires_grad=True)
w2 = torch.randn(256, 32, device=dev, requires_grad=True)
torch.compile(mlp, backend=inspect_backend)(x, w1, w2)
gm = graphs[0]
print(f"  {len(graphs)} graph; inputs: {[n.name for n in gm.graph.nodes if n.op == 'placeholder']}")
for n in gm.graph.nodes:
    if n.op not in ("placeholder", "output"):
        print(f"    {n.op:14} {str(n.target):42} args={[str(a) for a in n.args]}")

print("== B. graph breaks")
dynamo.reset()


def leaky(x):
    y = x.sin()
    print("    (print inside the compiled function runs in Python)")
    if y.sum().item() > 0:                               # data-dependent branch on a host value
        y = y * 2
    return y.cos()


ex = dynamo.explain(leaky)(x)
print(f"  explain(): {ex.graph_count} graphs, {ex.graph_break_count} graph breaks, {ex.op_count} ops captured")
for r in ex.break_reasons:
    print(f"    break: {r.reason.strip().splitlines()[0][:96]}")
try:
    torch.compile(leaky, backend="eager", fullgraph=True)(x)
except Exception as e:
    print(f"  fullgraph=True -> {type(e).__name__}: {str(e).strip().splitlines()[0][:80]}")

print("== C. guards and recompiles")
dynamo.reset()
records = []


class Keep(logging.Handler):
    def emit(self, rec):
        records.append(rec.getMessage())


torch._logging.set_logs(recompiles=True)
for name in ("torch._dynamo", "torch._dynamo.guards"):
    lg = logging.getLogger(name)
    lg.addHandler(Keep())
    lg.propagate = False                                 # keep the log in this process, off stderr
cnt = CompileCounter()


def scale(x, k):
    return x * k + 1


g = torch.compile(scale, backend=cnt)
calls = [("float32[8], k=2", torch.ones(8, device=dev), 2), ("float32[8], k=2 again", torch.ones(8, device=dev), 2),
         ("float32[16], k=2", torch.ones(16, device=dev), 2), ("float32[32], k=2", torch.ones(32, device=dev), 2),
         ("float32[1000], k=2", torch.ones(1000, device=dev), 2), ("float16[1000], k=2", torch.ones(1000, device=dev).half(), 2),
         ("float32[1000], k=3", torch.ones(1000, device=dev), 3), ("float32[1000], k=4", torch.ones(1000, device=dev), 4)]
for label, t, k in calls:
    before, seen = cnt.frame_count, len(records)
    g(t, k)
    why = [ln.strip()[2:].split("#")[0].strip() for m in records[seen:] if "guard failure" in m
           for ln in m.splitlines() if ln.strip().startswith("- 0/")]
    reason = f"  <- guard failed: {why[0][:64]}" if why else ""   # the newest cache entry's failed guard
    tag = "" if cnt.frame_count == before else "  (first compile)" if before == 0 else "  (recompiled)"
    print(f"  {label:22} compiles so far {cnt.frame_count}{tag}{reason}")
torch._logging.set_logs()

print("== D. AOTAutograd: one forward graph in, an ATen forward and backward graph out")


def chain(x, w):
    return torch.exp(torch.cos(torch.sin(w * x))).sum()  # pointwise chain: cheap to recompute, costly to save


wc = torch.randn(4096, device=dev, requires_grad=True)
for fn, args, params in ((mlp, (x, w1, w2), (w1, w2)), (chain, (x.flatten()[:4096], wc), (wc,))):
    print(f"  {fn.__name__}:")
    for label, part in (("default partitioner", None), ("min-cut rematerialization (Inductor's)", min_cut_rematerialization_partition)):
        dynamo.reset()
        seen = {}

        def fw(gm, inputs):
            outs = next(n for n in gm.graph.nodes if n.op == "output").args[0]
            seen["fw"], seen["saved"] = ops(gm), [a for a in outs[1:] if a.op != "placeholder"]
            seen["saved_inputs"] = sum(1 for a in outs[1:] if a.op == "placeholder")
            return make_boxed_func(gm.forward)

        def bw(gm, inputs):
            seen["bw"] = ops(gm)
            return make_boxed_func(gm.forward)

        kw = {"fw_compiler": fw, "bw_compiler": bw}
        if part is not None:
            kw["partition_fn"] = part
        for p in params:
            p.grad = None
        torch.compile(fn, backend=aot_autograd(**kw))(*args).backward()
        refs = torch.autograd.grad(fn(*args), params)
        assert all(torch.allclose(p.grad, r, rtol=1e-4, atol=1e-4) for p, r in zip(params, refs))
        saved = ", ".join(str(a.target).replace("aten.", "").replace(".default", "") for a in seen["saved"])
        print(f"    {label}: saves {seen['saved_inputs']} input(s) + {len(seen['saved'])} computed tensor(s) [{saved}]")
        print(f"      forward  {len(seen['fw']):2d} ops: {', '.join(seen['fw'])}")
        print(f"      backward {len(seen['bw']):2d} ops: {', '.join(seen['bw'])}")
print("ALL ASSERTIONS PASSED")
```

Output (deterministic, verified):

```text
== A. the FX graph a backend receives
  1 graph; inputs: ['l_x_', 'l_w1_', 'l_w2_']
    call_function  <built-in function matmul>                 args=['l_x_', 'l_w1_']
    call_function  <built-in function gelu>                   args=['matmul']
    call_function  <built-in function matmul>                 args=['h', 'l_w2_']
    call_method    relu                                       args=['matmul_1']
    call_method    sum                                        args=['relu']
== B. graph breaks
    (print inside the compiled function runs in Python)
  explain(): 3 graphs, 2 graph breaks, 1 ops captured
    break: Failed to trace builtin operator
    break: Unsupported Tensor.item() call with capture_scalar_outputs=False
  fullgraph=True -> Unsupported: Failed to trace builtin operator
== C. guards and recompiles
  float32[8], k=2        compiles so far 1  (first compile)
  float32[8], k=2 again  compiles so far 1
  float32[16], k=2       compiles so far 2  (recompiled)  <- guard failed: 0/0: tensor 'x' size mismatch at index 0. expected 8, actual 16
  float32[32], k=2       compiles so far 2
  float32[1000], k=2     compiles so far 2
  float16[1000], k=2     compiles so far 3  (recompiled)  <- guard failed: 0/1: tensor 'x' dtype mismatch. expected Float, actual Half
  float32[1000], k=3     compiles so far 4  (recompiled)  <- guard failed: 0/2: k == 2
  float32[1000], k=4     compiles so far 4
== D. AOTAutograd: one forward graph in, an ATen forward and backward graph out
  mlp:
    default partitioner: saves 2 input(s) + 3 computed tensor(s) [mm, gelu, detach]
      forward   6 ops: mm, gelu, mm, relu, detach, sum
      backward 10 ops: expand, detach, threshold_backward, t, mm, t, mm, gelu_backward, t, mm
    min-cut rematerialization (Inductor's): saves 0 input(s) + 5 computed tensor(s) [mm, detach, t, t, t]
      forward  10 ops: mm, gelu, mm, relu, detach, sum, detach, t, t, t
      backward  6 ops: expand, threshold_backward, mm, mm, gelu_backward, mm
  chain:
    default partitioner: saves 1 input(s) + 3 computed tensor(s) [mul.Tensor, sin, detach]
      forward   6 ops: mul.Tensor, sin, cos, exp, detach, sum
      backward  9 ops: expand, detach, mul.Tensor, sin, neg, mul.Tensor, cos, mul.Tensor, mul.Tensor
    min-cut rematerialization (Inductor's): saves 2 input(s) + 1 computed tensor(s) [detach]
      forward   7 ops: mul.Tensor, sin, cos, exp, detach, sum, detach
      backward 10 ops: expand, mul.Tensor, mul.Tensor, sin, sin, neg, mul.Tensor, cos, mul.Tensor, mul.Tensor
ALL ASSERTIONS PASSED
```

* **A**: the FX graph holds `matmul`, `gelu`, `matmul`, `relu`, `sum` with no Python left. Dynamo renamed inputs (`l_x_`) and kept the source variable `h`.
* **B**: `print` and `.item()` each split the function. The trap is "harmless" logging or host-side branching in the hot path, which quietly turns one graph into three with Python in between.
* **C**: the recompile log is the guard system described in §1.2. Python scalars that vary per call (`k`) recompile until they become dynamic. Pass them as tensors or mark them dynamic if they vary.
* **D**: AOTAutograd's two partitioners on the same graphs. Min-cut **recomputes the cheap pointwise chain** (saving 1 computed tensor instead of 3).

### 2.2 Fusion, launch overhead and compile cost

```python
"""inductor_fusion.py - what TorchInductor buys: fused Triton kernels, fewer HBM round trips, fewer launches.

A: x = sin(a) + cos(b) * c on 16M float32 (64 MiB per tensor). Eager runs 4 kernels and moves 11 tensors through
   HBM (sin: a -> t1, cos: b -> t2, mul: t2, c -> t3, add: t1, t3 -> x); Inductor's one Triton kernel moves 4 (a, b, c in,
   x out) and keeps t1..t3 in registers. Measured against the device's copy bandwidth.
B: the generated code: run_and_get_code returns the Triton source Inductor wrote.
C: a small MLP training step (launch-bound at batch 64): eager vs compile vs mode="reduce-overhead" (CUDA Graphs).
D: compile cost: first call (trace + codegen + Triton compile, cold caches) vs warm calls.
"""
import re
import time

import torch
from torch._inductor.utils import run_and_get_code

dev = torch.device("cuda")
torch.manual_seed(0)


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


def f(a, b, c):
    return torch.sin(a) + torch.cos(b) * c


print("== A. x = sin(a) + cos(b) * c, 16M float32 per tensor (64 MiB)")
a, b, c = (torch.randn(16 * 2**20, device=dev) for _ in range(3))
T = a.numel() * 4
copy_ms = gpu_ms(lambda: a.clone())
t0 = time.perf_counter()
compiled = torch.compile(f)
compiled(a, b, c)
torch.cuda.synchronize()
first_call = time.perf_counter() - t0
eager_ms, comp_ms = gpu_ms(lambda: f(a, b, c)), gpu_ms(lambda: compiled(a, b, c))
assert torch.allclose(f(a, b, c), compiled(a, b, c), atol=1e-5)
print(f"  a.clone() (2 tensor passes)          {copy_ms:6.3f} ms  {2 * T / copy_ms / 1e6:5.0f} GB/s  <- the roofline")
print(f"  eager: 4 kernels, 11 tensor passes   {eager_ms:6.3f} ms  {11 * T / eager_ms / 1e6:5.0f} GB/s achieved")
print(f"  compiled: 1 kernel, 4 tensor passes  {comp_ms:6.3f} ms  {4 * T / comp_ms / 1e6:5.0f} GB/s achieved  "
      f"({eager_ms / comp_ms:.1f}x; traffic ratio 11/4 = 2.75x)")

print("== B. the code Inductor generated")
torch._dynamo.reset()
_, code = run_and_get_code(torch.compile(f), a, b, c)
src = "\n".join(code)
kernels = re.findall(r"def (triton_\w+)\(", src)
print(f"  {len(kernels)} Triton kernel(s): {kernels}")
body = src[src.index(f"def {kernels[0]}("):]
for ln in body.splitlines()[1:40]:
    s = ln.strip()
    if re.match(r"(tmp\d+ = |tl\.store|x0 = |xindex = |xmask = )", s):
        print(f"    {s[:100]}")
    if s.startswith("tl.store"):
        break
assert len(kernels) == 1

print("== C. a training step that is launch-bound: 4-layer MLP, width 512, batch 64, AdamW")


def make():
    torch.manual_seed(1)
    m = torch.nn.Sequential(*[mod for _ in range(4) for mod in (torch.nn.Linear(512, 512), torch.nn.GELU())]).to(dev)
    return m, torch.optim.AdamW(m.parameters(), lr=1e-3)


xb, yb = torch.randn(64, 512, device=dev), torch.randn(64, 512, device=dev)


def step_fn(model, opt):
    def step():
        opt.zero_grad(set_to_none=True)
        loss = torch.nn.functional.mse_loss(model(xb), yb)
        loss.backward()
        opt.step()
        return loss
    return step


rows = []
for label, mode in (("eager", None), ("torch.compile (default)", "default"), ("torch.compile reduce-overhead", "reduce-overhead")):
    torch._dynamo.reset()
    model, opt = make()
    fwd = model if mode is None else torch.compile(model, mode=mode)
    step = step_fn(fwd, opt)
    t0 = time.perf_counter()
    for _ in range(3):
        step()
    torch.cuda.synchronize()
    warm = time.perf_counter() - t0
    ms = gpu_ms(step, reps=100)
    rows.append((label, ms, warm))
for label, ms, warm in rows:
    print(f"  {label:30} {ms:6.3f} ms/step  ({rows[0][1] / ms:4.1f}x)   first 3 steps incl. compile {warm:6.2f} s")

print("== D. compile cost is paid once per graph (and again per recompile)")
print(f"  f(a, b, c): first compiled call {first_call:5.2f} s vs {comp_ms:6.3f} ms per warm call "
      f"(break-even after ~{first_call * 1e3 / max(eager_ms - comp_ms, 1e-6):,.0f} calls)")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run, cold caches):

```text
== A. x = sin(a) + cos(b) * c, 16M float32 per tensor (64 MiB)
  a.clone() (2 tensor passes)           0.848 ms    158 GB/s  <- the roofline
  eager: 4 kernels, 11 tensor passes    3.989 ms    185 GB/s achieved
  compiled: 1 kernel, 4 tensor passes   1.583 ms    170 GB/s achieved  (2.5x; traffic ratio 11/4 = 2.75x)
== B. the code Inductor generated
  1 Triton kernel(s): ['triton_poi_fused_add_cos_mul_sin_0']
    xindex = xoffset + tl.arange(0, XBLOCK)[:]
    xmask = tl.full([XBLOCK], True, tl.int1)[:]
    x0 = xindex
    tmp0 = tl.load(in_ptr0 + (x0), None)
    tmp2 = tl.load(in_ptr1 + (x0), None)
    tmp4 = tl.load(in_ptr2 + (x0), None)
    tmp1 = tl_math.sin(tmp0)
    tmp3 = tl_math.cos(tmp2)
    tmp5 = tmp3 * tmp4
    tmp6 = tmp1 + tmp5
    tl.store(out_ptr0 + (x0), tmp6, None)
== C. a training step that is launch-bound: 4-layer MLP, width 512, batch 64, AdamW
  eager                           1.619 ms/step  ( 1.0x)   first 3 steps incl. compile   0.17 s
  torch.compile (default)         1.570 ms/step  ( 1.0x)   first 3 steps incl. compile   1.67 s
  torch.compile reduce-overhead   1.163 ms/step  ( 1.4x)   first 3 steps incl. compile   0.58 s
== D. compile cost is paid once per graph (and again per recompile)
  f(a, b, c): first compiled call  3.53 s vs  1.583 ms per warm call (break-even after ~1,466 calls)
ALL ASSERTIONS PASSED
```

* **Fusion is a bandwidth win.** Both versions run near the device's copy bandwidth (eager's "achieved" can slightly exceed `clone()`'s because pure streaming kernels with no allocation are efficient). The speedup (~2.5×) comes from moving 4 tensors instead of 11, not from faster arithmetic.
* **The training step at batch 64** is launch-bound. Default compile helped little (~1.0–1.1×): the optimizer's `foreach` kernels and the remaining launches dominate. `reduce-overhead` (CUDA Graphs) gave ~1.4–1.7× by replacing hundreds of launches with replays.
* **Compile time is real.** One tiny kernel took ~3.4–4.9 s on first call (Dynamo, AOTAutograd, Inductor, Triton → PTX → cubin), so break-even was ~800–2,000 calls. For training that's noise. For autoscaled inference pods it's a cold-start problem (§4, Q6).

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Compiled model gets slower over time | `TORCH_LOGS=recompiles` shows many entries; "recompile_limit (8) reached" | Varying shapes, Python scalars, changing attributes | `torch._dynamo.mark_dynamic`, `dynamic=True`, pass scalars as 0-d tensors, bucket shapes | Count compiles in CI with a fixed shape mix |
| F2 ⚡ | Little or no speedup | `TORCH_LOGS=graph_breaks` lists breaks | `print`, `.item()`, unsupported libraries, data-dependent control flow | Move host work out, `torch.cond`, `capture_scalar_outputs=True` | `fullgraph=True` in tests for the hot module |
| F3 🔥 | First request after a deploy takes 30–120 s | Compile on first call per shape | JIT on the critical path | Warm up before the readiness probe; persistent caches; AOTInductor | Track compile time as a deploy metric |
| F4 🔥 | `RuntimeError: accessing tensor output of CUDAGraphs that has been overwritten by a subsequent run` | `reduce-overhead` mode | Graph outputs live in a reused pool | `.clone()` outputs you keep; `torch.compiler.cudagraph_mark_step_begin()` | Treat graph outputs as borrowed |
| F5 | GPU memory grows with each new input shape | `reduce-overhead` + varying shapes | One CUDA-graph pool per shape | Bucket/pad shapes; `dynamic=False` with few buckets | Bound distinct shapes |
| F6 | Small numerical differences vs eager | 1e-6 relative in fp32 | Fused math reassociates; FMA contraction | Accept tolerance; compare with `backend="aot_eager"` to isolate Inductor | Tolerance-based parity tests |
| F7 | Compile error only in Inductor | Works with `backend="aot_eager"` | Codegen/lowering bug or unsupported op | Bisect backends; minifier (`TORCHDYNAMO_REPRO_AFTER="aot"`) | Pin versions; report with the minified repro |
| F8 ⚠ | Triton fails to build on Windows | `Failed to find C compiler` / CUDA toolkit warnings | Triton needs a C compiler for its launcher and `ptxas` | triton-windows + `CC` pointing at a working compiler (bundled TinyCC here) | Use Linux for production compile workers |
| F9 | Matmul-heavy model doesn't speed up | Kernels are cuBLAS before and after | Nothing to fuse; GEMM already optimal | Expect gains from pointwise/norm fusion only; try `max-autotune` on big GPUs | Profile the kernel mix before promising speedups |

**Debugging toolkit.** `TORCH_LOGS="graph_breaks,recompiles,guards,output_code"`; `torch._dynamo.explain(fn)(*args)`; `torch._inductor.utils.run_and_get_code(fn, *args)` (the generated source); `TORCH_COMPILE_DEBUG=1` (dumps every stage); `tlparse` on the structured trace log (⚠ not run here); backend bisection `"eager"` → `"aot_eager"` → `"inductor"`; `torch.compiler.reset()` between experiments.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Explain what `torch.compile` actually does."</b></summary>

**Initial Prompt.** A team asks whether to enable `torch.compile` on their training job. Explain the mechanism.

**L5 Answer.** "It converts the model to a static graph like TensorFlow and optimizes it."

**Why L5 Crashes at Scale.** "Static graph" predicts the wrong failure modes. Dynamo keeps Python semantics: unsupported code falls back to the interpreter (graph breaks), and guards cause recompiles when inputs change. Teams expecting all-or-nothing behaviour don't look for either and ship a model that's half eager.

**L7 Principal Defense.** Four layers. Dynamo hooks CPython frame evaluation via PEP 523, symbolically executes bytecode, records tensor ops into FX graphs with guards (dtype, shape, constants), and resumes in Python at unsupported code. AOTAutograd traces forward and backward to ATen with fake tensors, functionalizes, and partitions what to save vs recompute (min-cut). Inductor fuses pointwise and reduction chains into Triton kernels and keeps matmuls on cuBLAS. Optionally CUDA Graphs remove launch overhead. Expected wins: memory-bound pointwise chains (measured ~2.5× for a 4-op chain, matching the 2.75× traffic ratio) and launch-bound small batches with `reduce-overhead` (~1.4–1.7×). Little gain for GEMM-dominated models. Roll out with `TORCH_LOGS=graph_breaks,recompiles` and a compile-count check.

</details>

<details><summary><b>Q2 · "Production latency doubled after we enabled `torch.compile`."</b></summary>

**Initial Prompt.** A recommendation model with variable-length inputs got slower after compilation.

**L5 Answer.** "Compilation doesn't work for this model; turn it off."

**Why L5 Crashes at Scale.** It discards the optimization without diagnosing the cause, which is almost always guards. Each new sequence length fails a static size guard. Recompiles happen on the request path until the per-frame limit (8) is hit, and then that frame runs **eagerly forever**, having paid every compile along the way.

**L7 Principal Defense.** Confirm with `TORCH_LOGS=recompiles`. The listing's log line (`size mismatch at index 0. expected 8, actual 16`) is the signature. Then fix the shape regime. Mark the varying dimension dynamic up front (`mark_dynamic(x, 1)` or `dynamic=True`), so one symbolic graph serves all lengths (measured: sizes 16, 32 and 1000 reused one entry). Or bucket lengths to a few padded sizes, which also enables CUDA Graphs per bucket. Pass varying Python scalars as tensors. Warm up every bucket before taking traffic and alert on compile events after warm-up.

</details>

<details><summary><b>Q3 · "Why is a fused kernel faster if it does the same arithmetic?"</b></summary>

**Initial Prompt.** Justify fusion with numbers for `x = sin(a) + cos(b) * c` on 16 M floats.

**L5 Answer.** "Fewer kernel launches."

**Why L5 Crashes at Scale.** Launch count matters for small tensors. At 64 MiB per tensor, launches are microseconds against milliseconds of memory traffic. The real model is the roofline: these ops do ~1 FLOP per 4 bytes, far below the GPU's compute-to-bandwidth ratio, so time = bytes moved ÷ bandwidth.

**L7 Principal Defense.** Count DRAM passes. Eager runs 4 kernels and moves 11 tensors (each intermediate is written then read back). The fused Triton kernel reads 3 and writes 1, keeping intermediates in registers: ideal speedup 11/4 = 2.75×, measured ~2.5×, with both near the device's copy bandwidth. So fusion matters most for long pointwise/normalization chains around matmuls (bias, activation, dropout, residual, LayerNorm), the bulk of a transformer's non-GEMM time. The same arithmetic intensity reasoning decides FlashAttention (07.2).

</details>

<details><summary><b>Q4 · "How do we find and fix graph breaks?"</b></summary>

**Initial Prompt.** `torch.compile` gave 5 %, not the expected 30 %.

**L5 Answer.** "Try `mode='max-autotune'`."

**Why L5 Crashes at Scale.** Autotuning optimizes the kernels inside graphs. If the model is split into many small graphs by breaks, each boundary forces intermediate results to memory and returns to Python, and autotuning can't fix that. It also multiplies compile time.

**L7 Principal Defense.** Measure the graph structure: `torch._dynamo.explain(model)(inputs)` gives graph count, break count and reasons (the listing shows `print` and `.item()`), and `TORCH_LOGS=graph_breaks` gives file and line. The usual causes and fixes: logging or `.item()` in `forward` (move it out, or log every N steps outside); data-dependent Python branches (`torch.where`, `torch.cond`); unsupported third-party calls (wrap them as custom ops with `torch.library.custom_op` so Dynamo treats them as one node); NumPy calls (Dynamo can trace many). Lock it in with `fullgraph=True` on the hot module in CI.

</details>

<details><summary><b>Q5 · "Should our inference service use `mode='reduce-overhead'`?"</b></summary>

**Initial Prompt.** Small-batch online inference, p50 dominated by kernel launch time.

**L5 Answer.** "Yes, it's always faster."

**Why L5 Crashes at Scale.** CUDA Graphs freeze input addresses and shapes. Variable request shapes create one graph and one memory pool each, so memory grows with shape diversity. Outputs live in a reused pool and are overwritten by the next replay (the F4 error) if a handler keeps them. Concurrent requests on threads sharing one graph need care.

**L7 Principal Defense.** It's the right tool for launch-bound serving: measured ~1.4–1.7× on a small MLP step, and 7.5–9.2× on a pure launch microbenchmark (06.1). Constrain shapes first (pad to a few batch-size and length buckets), warm every bucket at startup, `.clone()` outputs that outlive the call, and budget memory per bucket. Measure p99 as well as p50: a bucket miss falls back to a compile or eager path. For LLM decode loops, which are the extreme launch-bound case, serving engines use CUDA Graphs per batch size for exactly this reason.

</details>

<details><summary><b>Q6 · "Autoscaled pods take 90 seconds to serve their first request."</b></summary>

**Initial Prompt.** A compiled model deploys on Kubernetes with HPA; cold pods time out.

**L5 Answer.** "Increase the readiness timeout."

**Why L5 Crashes at Scale.** Compilation is per process and per shape. Every new pod recompiles everything (measured ~3.4–4.9 s for a single tiny kernel, minutes for a large model), so scale-out events are slowest exactly when load spikes. A longer timeout only hides it.

**L7 Principal Defense.** Move compilation off the request path. (1) Warm up all shape buckets before the readiness probe passes. (2) Ship persistent caches: Inductor's FX-graph cache and Triton's kernel cache on a shared volume or baked into the image, keyed by exact torch/Triton/driver/GPU versions. (3) Use **ahead-of-time compilation** (`torch.export` + AOTInductor): a packaged shared library with no Dynamo or JIT at runtime. (4) Keep a warm pool for spikes. Track compile seconds as a deploy SLO.

</details>

<details><summary><b>Q7 · "TorchScript, `torch.compile` or `torch.export` for deployment?"</b></summary>

**Initial Prompt.** Choose the model artifact format for a C++ serving stack.

**L5 Answer.** "TorchScript; it's what we used before."

**Why L5 Crashes at Scale.** TorchScript is in maintenance mode, with its own language subset and frontend. New operator and compiler work targets the Dynamo/export stack, so TorchScript models fall behind on performance and on support for new models.

**L7 Principal Defense.** `torch.compile` is a JIT for Python-hosted execution: graph breaks are allowed and Python remains. `torch.export` is **sound full-graph capture** with no Python fallback: it produces an `ExportedProgram` of core ATen ops with explicit dynamic-shape constraints, or fails with an explanation. That's what a C++ or edge deployment needs. Compile it with AOTInductor into a `.pt2` package that runs from C++ without Python, or lower it to other runtimes (ExecuTorch, TensorRT, ONNX via the dynamo exporter). Python services use `torch.compile`; non-Python runtimes use `export`, with dynamic dims declared and tested.

</details>

<details><summary><b>Q8 · "Explain Dynamo to a JVM performance engineer."</b></summary>

**Initial Prompt.** Map Dynamo's design to HotSpot concepts.

**L5 Answer.** "It's like a JIT compiler for Python."

**Why L5 Crashes at Scale.** The analogy is useful only with the specifics, which predict the operational behaviour: why recompiles happen, why some code is never optimized, what the warm-up looks like.

**L7 Principal Defense.** PEP 523 is the hook where HotSpot's interpreter hands a hot method to C2. Guards are speculative assumptions (type profiles become dtype/shape/value guards), and a failed guard is an uncommon trap: deoptimize and recompile. `recompile_limit = 8` plays the role of `PerMethodRecompilationCutoff`: past it the frame stays interpreted (eager). A graph break is a call site the JIT won't inline (a native or megamorphic call), splitting optimized regions. AOTAutograd's min-cut partitioner is rematerialization in a register allocator, recomputing cheap values instead of spilling them (measured: 3 saved tensors → 1). Inductor is C2's backend, and Triton is the instruction selector for GPUs. The operational advice carries over too: warm up, keep call sites monomorphic (stable shapes and dtypes), and watch the compile log.

</details>

<details><summary><b>Q9 · "When should we write a Triton kernel ourselves?"</b></summary>

**Initial Prompt.** A researcher wants to hand-write Triton for a custom attention variant.

**L5 Answer.** "Always: hand-written kernels are fastest."

**Why L5 Crashes at Scale.** A hand-written kernel must be maintained across GPU generations, dtypes and shapes, needs its own autograd (backward kernel), and opts out of Inductor's fusion with neighbouring ops. For most pointwise or reduction patterns Inductor already generates what you'd write (the listing's kernel is the textbook fused loop).

**L7 Principal Defense.** Let Inductor handle pointwise, reduction and normalization fusion; check its output with `run_and_get_code`. Write Triton when the algorithm needs a schedule the compiler won't discover: tiling with online-softmax recurrences (FlashAttention), fused quantize/dequantize-GEMM for low-bit weights, custom sparse or ragged layouts. Register it with `torch.library.triton_op` or a custom op so Dynamo treats it as one node, write the backward (or a `torch.autograd.Function`), and test it against the eager reference across shapes and dtypes. Folder 07.2 does this analysis for attention.

</details>

---

## 5. Invariants Checklist

- [ ] Dynamo captures FX graphs from bytecode via PEP 523. Unsupported code is a graph break, not an error, unless `fullgraph=True`.
- [ ] Every compiled entry is guarded. Shape, dtype and Python-constant changes recompile, and after 8 entries per frame Dynamo falls back to eager.
- [ ] Automatic dynamic shapes make a dimension symbolic after its first change. Declare dynamic dims up front when you know them.
- [ ] AOTAutograd traces forward + backward ahead of time. The min-cut partitioner recomputes cheap ops instead of saving them.
- [ ] Inductor fuses memory-bound chains into Triton kernels. The win is bytes moved (11 → 4 passes, ~2.5× measured), not FLOPs.
- [ ] Matmuls stay on cuBLAS unless `max-autotune` runs on a big GPU.
- [ ] `reduce-overhead` = CUDA Graphs: static shapes and addresses, pooled outputs, memory per shape.
- [ ] Compile cost is seconds to minutes per process. Warm up, cache, or compile ahead of time for serving.

---

## 6. References

- J. Ansel et al., "PyTorch 2: Faster Machine Learning Through Dynamic Python Bytecode Transformation and Graph Compilation", ASPLOS 2024, DOI 10.1145/3620665.3640366
- PEP 523 — Adding a frame evaluation API to CPython — https://peps.python.org/pep-0523/
- PyTorch docs: `torch.compiler` overview — https://docs.pytorch.org/docs/stable/torch.compiler.html
- PyTorch docs: `torch.compile` API — https://docs.pytorch.org/docs/stable/generated/torch.compile.html
- PyTorch docs: `torch.export` — https://docs.pytorch.org/docs/stable/export.html
- PyTorch `_dynamo/config.py` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/torch/_dynamo/config.py
- PyTorch `_functorch/partitioners.py` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/torch/_functorch/partitioners.py
- PyTorch `_inductor/config.py` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/torch/_inductor/config.py
- P. Tillet, H. T. Kung, D. Cox, "Triton: An Intermediate Language and Compiler for Tiled Neural Network Computations", MAPL 2019, DOI 10.1145/3315508.3329973
- OpenAI Triton — https://github.com/triton-lang/triton
- triton-windows (community Windows build, used here) — https://github.com/woct0rdho/triton-windows
