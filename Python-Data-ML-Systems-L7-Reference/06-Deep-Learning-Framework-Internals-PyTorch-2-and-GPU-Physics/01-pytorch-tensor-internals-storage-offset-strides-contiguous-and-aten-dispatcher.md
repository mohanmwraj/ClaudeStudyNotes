# 06.1 · PyTorch Tensor Internals: Storage, Offset, Strides, Contiguity & the ATen Dispatcher

> **Folder 06 · Deep Learning Framework Internals: PyTorch 2 & GPU Physics**
> **Measured on:** PyTorch 2.14.1+cu130 (CUDA 13.0 wheel), **NVIDIA GeForce RTX 3050 Laptop GPU** (Ampere GA107, sm_86, 16 SMs, 4 GB GDDR6, driver 610.78), i5-11260H (6C/12T), Windows 11 (WDDM driver model), CPython 3.14.5.
> **Source quoted:** the C++ headers shipped inside the installed wheel (`torch/include/c10/core/TensorImpl.h`, `StorageImpl.h`, `DispatchKey.h`, `torch/csrc/autograd/python_variable.h`), which match tag `v2.14.1`.

---

## 0. Orientation & the JVM/C++ Bridge

A PyTorch tensor is two objects. A small **metadata header** (`TensorImpl`: sizes, strides, offset, dtype, device, autograd slot) points at a refcounted **byte buffer** (`StorageImpl`) in CPU RAM or GPU memory. Most "reshaping" operations only build a new header over the same bytes. Every operator call then goes through the **dispatcher**, a per-operator table indexed by a 64-bit key set, which decides whether autograd, autocast, functionalization or a backend kernel runs next. Two physical facts dominate GPU performance at this level: memory traffic (contiguous vs strided copies) and per-op host overhead (Python → dispatcher → kernel launch).

| PyTorch | JVM analogue | C/C++ analogue |
|---|---|---|
| `TensorImpl` over `StorageImpl` | `ByteBuffer.slice()` / `duplicate()`: new position/limit over shared content | `std::mdspan` with `layout_stride`; Eigen `Map<..., Stride<>>` |
| `c10::intrusive_ptr` refcount (in the object) | GC reachability | `boost::intrusive_ptr`; `std::shared_ptr` with `make_shared` |
| a view pinning a huge storage | `String.substring` sharing `char[]` before JDK 7u6 | a `std::string_view` keeping a buffer alive (by contract) |
| `DispatchKeySet` → kernel table | megamorphic virtual call + inline cache, decided per call | a function-pointer table indexed by the highest set bit |
| CUDA stream (FIFO of kernels) | a single-threaded `ExecutorService` queue | a lock-free SPSC queue drained by the device |
| `.item()` / `.cpu()` | `Future.get()` | `cudaStreamSynchronize` |
| caching allocator | TLAB / arena allocation, never returned to the OS | a slab allocator over `cudaMalloc` |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 From a Python name to a GPU byte

```text
 Python name `x`
   │
   ▼
 THPVariable (python_variable.h)              PyObject_HEAD | at::Tensor cdata | backward_hooks | post_acc_grad_hooks ...
   │  cdata = c10::intrusive_ptr<TensorImpl>
   ▼
 TensorImpl (TensorImpl.h, ≤ 26 x 8 = 208 B on 64-bit, enforced by check_sizes())
   vtable ptr | refcount_ + weakcount_ (intrusive_ptr_target)
   storage_               8  -> intrusive_ptr<StorageImpl>
   autograd_meta_       ≤16  -> AutogradMeta (grad_, grad_fn_, requires_grad_, is_view_, output_nr_, hooks) or null
   extra_meta_          ≤16  (symbolic shapes, named dims)        version_counter_ 8 (shared by a base and its views)
   pyobj_slot_            8  -> back-pointer to the THPVariable   sizes_and_strides_ 88 (inline up to 5 dims)
   storage_offset_        8 | numel_ 8 | data_type_ 2 | device_opt_ 3 | is_contiguous_, is_channels_last_... (bitfields)
   key_set_               8  DispatchKeySet: which dispatcher layers apply to this tensor
   │
   ▼
 StorageImpl (StorageImpl.h)                  shared by every view of the same bytes
   data_ptr_  (DataPtr: void* data, deleter context, Device)    size_bytes_ (SymInt)    resizable_
   allocator_ (CPU allocator, CUDA caching allocator, pinned-host allocator...)    pyobj_slot_
   │
   ▼
 bytes: [ e0 e1 e2 ... ]  in host RAM or GPU DRAM (GDDR6 here, HBM in datacenter parts)
```

Three consequences follow from the diagram. A tensor costs a few hundred bytes of metadata regardless of its size, so a million tiny tensors are a memory and dispatch disaster. Views are cheap because they allocate only a `TensorImpl`. And the **storage lives as long as any view of it does**: a 4-byte slice can pin a 10 GB buffer.

### 1.2 Addressing: one formula for every view

```text
 address(i0, i1, ..., ik) = storage.data + itemsize * (storage_offset + Σ i_d * stride_d)

 base = arange(24).reshape(4, 6)      size (4, 6)  stride (6, 1)  offset 0    contiguous (row-major)
 base.T                               size (6, 4)  stride (1, 6)  offset 0    same bytes, swapped strides
 base[1:, ::2]                        size (3, 3)  stride (6, 2)  offset 6    start at row 1, every other column
 base[:, 3]                           size (4,)    stride (6,)    offset 3    a column: strided
 base.unsqueeze(0).expand(5, 4, 6)    size (5,4,6) stride (0,6,1)             stride 0: one row of bytes seen 5 times
```

🧊 **PyTorch strides are in elements; NumPy strides are in bytes.** `torch.from_numpy` and DLPack convert between them. Code ported from NumPy that does stride arithmetic by hand silently goes wrong by a factor of the item size.

### 1.3 `view` vs `reshape` vs `contiguous`

```text
 t.view(shape)      metadata only. Succeeds iff the new shape can be expressed with strides over the SAME storage
                    (each merged dimension group must be contiguous with itself). Otherwise: RuntimeError.
 t.reshape(shape)   = view when possible, else contiguous() + view: may allocate and copy (you can't tell from the call)
 t.contiguous()     returns t itself if already contiguous; else allocates numel * itemsize and copies with a strided read
 t.T.view(24)       fails: rows of t.T are strided by 6 in the storage, so no single stride walks them in order
```

The copy is not free. Measured on the RTX 3050 for 64 MiB float32: `clone()` (contiguous read, contiguous write) runs at ~130–160 GB/s. `x.T.contiguous()` runs at ~62–64 GB/s, because one side of a transposing copy is strided and its 32-byte memory sectors are only partly used. ⚠ The GPU's spec bandwidth is 192–224 GB/s depending on the OEM's memory clock.

### 1.4 The dispatcher: what `a + b` does before any arithmetic

```text
 Python: a + b
  -> THPVariable_add (generated binding): PythonArgParser matches the overload, unpacks THPVariables      ~1 µs
  -> at::add(a, b) -> Dispatcher::call(op_handle "aten::add.Tensor")
       key set = (a.key_set_ | b.key_set_ | TLS included) - TLS excluded
       pick the highest-priority functionality key in the set, then its backend bit
  -> e.g. AutocastCUDA  (cast inputs if autocast is on, redispatch below itself)
  -> AutogradCUDA       (if any input requires grad: create AddBackward0, record edges, save what backward needs)
  -> ADInplaceOrView    (bump version counters, set up view metadata for in-place/view ops)
  -> CUDA               (the real kernel: compute output size/dtype, allocate from the caching allocator,
                         launch the kernel into the current stream, return)
```

Measured key sets: a float CUDA tensor carries `CUDA, ADInplaceOrView, AutogradCUDA, AutocastCUDA` **whether or not it requires grad**. The autograd layer decides at runtime whether to record anything. That's why `torch.inference_mode()` is faster than `no_grad()`. It puts the autograd and `ADInplaceOrView` keys in the TLS **excluded** set, so those layers are skipped outright, and inference tensors skip version-counter bookkeeping. Measured on the CPU for an 8-element add: NumPy ~0.4 µs, torch ~2.1–2.5 µs, torch with `requires_grad` ~4.0–4.6 µs (graph recording), inference mode ~1.9–2.2 µs.

### 1.5 The asynchronous device

```text
 CPU thread                                  GPU
 x = x + 1   -> launch K1 into stream 0  ──► [K1]
 x = x + 1   -> launch K2 (returns at once) ──►    [K2]
 ...                                                      queue drains in order
 x[0].item() -> cudaMemcpy D2H + wait  ◄── blocks until K1..Kn have finished
```

A CUDA launch on Windows WDDM costs ~17–20 µs of CPU time here. ⚠ Linux's TCC/open driver is typically a few µs. A 1,024-element add runs in a few µs on the GPU, so a loop of tiny ops is **launch-bound**: the GPU waits for the CPU. Synchronization points make it worse because they forbid run-ahead: `.item()`, `.cpu()`, `.tolist()`, `print(t)`, `if t:`, `torch.nonzero`, boolean-mask indexing (output shape depends on data), and `torch.cuda.synchronize()`. **CUDA Graphs** record a sequence of launches once and replay it as one launch. Addresses, shapes and kernel arguments are frozen, so inputs must be copied into static buffers.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Views, storage sharing, hidden copies and memory formats

```python
"""tensor_anatomy.py - TensorImpl metadata vs StorageImpl bytes: views, strides, contiguity and hidden copies.

A tensor = (storage, storage_offset, sizes, strides, dtype, device) + autograd metadata. Views share the storage;
.view() requires a stride-compatible layout; .reshape()/.contiguous() allocate when it isn't. Measured on CUDA:
data_ptr / storage identity, bytes allocated by the caching allocator, and the cost of making a transpose contiguous.
"""
import time

import numpy as np
import torch

dev = torch.device("cuda")
print(f"torch {torch.__version__}, device {torch.cuda.get_device_name(0)}")
print("== A. one storage, many tensors")
base = torch.arange(24, dtype=torch.float32, device=dev).reshape(4, 6)
S = base.untyped_storage().data_ptr()
rows = []
for label, t in [("base (4,6)", base), ("base.T", base.T), ("base[1:, ::2]", base[1:, ::2]),
                 ("base[:, 3]", base[:, 3]), ("base.unsqueeze(0).expand(5,4,6)", base.unsqueeze(0).expand(5, 4, 6)),
                 ("base.view(2,12)", base.view(2, 12)), ("base.permute(1,0).reshape(24)", base.permute(1, 0).reshape(24)),
                 ("base.T.contiguous()", base.T.contiguous())]:
    shares = t.untyped_storage().data_ptr() == S
    print(f"  {label:34} size={str(tuple(t.shape)):12} stride={str(t.stride()):12} offset={t.storage_offset():2} "
          f"contiguous={t.is_contiguous()!s:5} {'shares storage' if shares else 'NEW storage'}")
try:
    base.T.view(24)
except RuntimeError as e:
    print(f"  base.T.view(24) -> RuntimeError: {str(e).splitlines()[0][:90]}...")
assert base.T.reshape(24).untyped_storage().data_ptr() != S       # reshape had to copy

print("== B. what a contiguous copy costs on the GPU (4096 x 4096 float32 = 64 MiB)")
x = torch.randn(4096, 4096, device=dev)
torch.cuda.synchronize()


def gpu_time(fn, reps=20):
    fn()
    torch.cuda.synchronize()
    start, end = torch.cuda.Event(enable_timing=True), torch.cuda.Event(enable_timing=True)
    start.record()
    for _ in range(reps):
        out = fn()
    end.record()
    torch.cuda.synchronize()
    return start.elapsed_time(end) / reps, out


for label, fn in [("x.T (metadata only)", lambda: x.T), ("x.clone() (contiguous copy)", lambda: x.clone()),
                  ("x.T.contiguous() (transposing copy)", lambda: x.T.contiguous()),
                  ("x.T.reshape(-1) (forced copy)", lambda: x.T.reshape(-1))]:
    before = torch.cuda.memory_allocated()
    ms, out = gpu_time(fn)
    new = torch.cuda.memory_allocated() - before
    bw = 2 * x.numel() * 4 / (ms / 1e3) / 1e9 if new else 0.0
    print(f"  {label:38} {ms:7.3f} ms   new allocation {new / 2**20:5.0f} MiB" + (f"   {bw:5.0f} GB/s" if new else ""))
    del out

print("== C. zero-copy bridges on the CPU")
a = np.arange(10, dtype=np.float32)
t = torch.from_numpy(a)
t[0] = 42.0
print(f"  torch.from_numpy shares memory: a[0] = {a[0]} after t[0] = 42; same address: "
      f"{t.data_ptr() == a.ctypes.data}")
back = np.from_dlpack(t)
print(f"  np.from_dlpack(t) shares memory: {back.ctypes.data == t.data_ptr()}")
copy = torch.tensor(a)
print(f"  torch.tensor(a) copies: {copy.data_ptr() != a.ctypes.data}")
assert t.data_ptr() == a.ctypes.data and back.ctypes.data == t.data_ptr()

print("== D. memory formats: NCHW contiguous vs channels_last (NHWC strides) for a cuDNN convolution (fp16)")
conv = torch.nn.Conv2d(64, 64, 3, padding=1).to(dev).half()
inp = torch.randn(32, 64, 112, 112, device=dev, dtype=torch.float16)
for label, fmt in [("contiguous (NCHW)", torch.contiguous_format), ("channels_last (NHWC)", torch.channels_last)]:
    c = conv.to(memory_format=fmt)
    xi = inp.contiguous(memory_format=fmt)
    with torch.no_grad():
        ms, _ = gpu_time(lambda: c(xi), reps=20)
    print(f"  {label:22} input stride {str(xi.stride()):24} conv {ms:6.2f} ms")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
torch 2.14.1+cu130, device NVIDIA GeForce RTX 3050 Laptop GPU
== A. one storage, many tensors
  base (4,6)                         size=(4, 6)       stride=(6, 1)       offset= 0 contiguous=True  shares storage
  base.T                             size=(6, 4)       stride=(1, 6)       offset= 0 contiguous=False shares storage
  base[1:, ::2]                      size=(3, 3)       stride=(6, 2)       offset= 6 contiguous=False shares storage
  base[:, 3]                         size=(4,)         stride=(6,)         offset= 3 contiguous=False shares storage
  base.unsqueeze(0).expand(5,4,6)    size=(5, 4, 6)    stride=(0, 6, 1)    offset= 0 contiguous=False shares storage
  base.view(2,12)                    size=(2, 12)      stride=(12, 1)      offset= 0 contiguous=True  shares storage
  base.permute(1,0).reshape(24)      size=(24,)        stride=(1,)         offset= 0 contiguous=True  NEW storage
  base.T.contiguous()                size=(6, 4)       stride=(4, 1)       offset= 0 contiguous=True  NEW storage
  base.T.view(24) -> RuntimeError: view size is not compatible with input tensor's size and stride (at least one dimension sp...
== B. what a contiguous copy costs on the GPU (4096 x 4096 float32 = 64 MiB)
  x.T (metadata only)                      0.005 ms   new allocation     0 MiB
  x.clone() (contiguous copy)              1.029 ms   new allocation    64 MiB     130 GB/s
  x.T.contiguous() (transposing copy)      2.161 ms   new allocation    64 MiB      62 GB/s
  x.T.reshape(-1) (forced copy)            2.101 ms   new allocation    64 MiB      64 GB/s
== C. zero-copy bridges on the CPU
  torch.from_numpy shares memory: a[0] = 42.0 after t[0] = 42; same address: True
  np.from_dlpack(t) shares memory: True
  torch.tensor(a) copies: True
== D. memory formats: NCHW contiguous vs channels_last (NHWC strides) for a cuDNN convolution (fp16)
  contiguous (NCHW)      input stride (802816, 12544, 112, 1)  conv   4.95 ms
  channels_last (NHWC)   input stride (802816, 1, 7168, 64)    conv   3.35 ms
ALL ASSERTIONS PASSED
```

* Every row marked `shares storage` cost a `TensorImpl` and nothing else. `permute(1,0).reshape(24)` and `T.contiguous()` allocated **new storage**. `reshape` gives no syntactic hint, so in hot paths assert `t.is_contiguous()` or use `view` to make an accidental copy fail loudly.
* A transposing copy ran at roughly **half the bandwidth** of a straight copy (~62–64 vs ~130–160 GB/s). Copying a permuted tensor isn't "just a memcpy".
* `torch.from_numpy` and `np.from_dlpack` are zero-copy. `torch.tensor(ndarray)` always copies. A write through either side of a zero-copy bridge is visible on the other.
* **`channels_last`** (NHWC strides on a logically NCHW tensor) made the fp16 cuDNN 3×3 convolution ~1.35–1.5× faster (≈ 4.7–5.0 ms → ≈ 3.35–3.45 ms). Tensor-core convolution kernels want channels innermost. Convert the model and its inputs once; mixing formats inserts a conversion per layer.

### 2.2 The per-op tax and how to stop paying it

```python
"""dispatch_launch_overhead.py - the per-op tax: ATen dispatcher keys, autograd bookkeeping, async CUDA launches, CUDA Graphs.

A: the dispatch key set a tensor carries (each key is a layer an op may pass through).
B: per-op cost of a tiny add on CPU: NumPy vs torch, with and without autograd tracking.
C: CUDA is asynchronous: the CPU enqueues kernels and returns; .item() forces a host-device sync.
D: CUDA Graphs replay a captured sequence of 200 tiny kernels with one launch.
"""
import time

import numpy as np
import torch

dev = torch.device("cuda")
print("== A. dispatch keys")
for label, t in [("CPU float", torch.ones(2)), ("CPU float, requires_grad", torch.ones(2, requires_grad=True)),
                 ("CUDA float", torch.ones(2, device=dev)), ("CUDA float, requires_grad", torch.ones(2, device=dev, requires_grad=True))]:
    keys = str(torch._C._dispatch_keys(t)).replace("DispatchKeySet(", "").rstrip(")")
    print(f"  {label:26} {keys}")


def per_call(fn, n=20_000):
    fn()
    t0 = time.perf_counter()
    for _ in range(n):
        fn()
    return (time.perf_counter() - t0) / n * 1e6


print("== B. one tiny add (8 elements) on the CPU, us per call")
an, bn = np.ones(8), np.ones(8)
at, bt = torch.ones(8), torch.ones(8)
ag = torch.ones(8, requires_grad=True)
rows = [("NumPy a + b", per_call(lambda: an + bn)), ("torch a + b", per_call(lambda: at + bt)),
        ("torch a + b, a.requires_grad", per_call(lambda: ag + bt))]
with torch.inference_mode():
    rows.append(("torch a + b under inference_mode", per_call(lambda: ag + bt)))
for label, us in rows:
    print(f"  {label:34} {us:6.2f} us")

print("== C. asynchronous CUDA execution")
x = torch.ones(1024, device=dev)
torch.cuda.synchronize()
t0 = time.perf_counter()
for _ in range(2000):
    x = x + 1                                            # each line = one kernel launch, returns immediately
t_enqueue = time.perf_counter() - t0
torch.cuda.synchronize()
t_done = time.perf_counter() - t0
t0 = time.perf_counter()
for _ in range(2000):
    x = x + 1
    _ = x[0].item()                                      # copy one value to the host: waits for the GPU each time
t_sync = time.perf_counter() - t0
print(f"  2000 tiny kernels: Python returns after {t_enqueue * 1e3:6.1f} ms; GPU finishes at {t_done * 1e3:6.1f} ms "
      f"({t_enqueue / 2000 * 1e6:.1f} us per launch)")
print(f"  same loop with x[0].item() every step: {t_sync * 1e3:6.1f} ms ({t_sync / t_done:.1f}x: no overlap of CPU and GPU)")

print("== D. CUDA Graphs: 200 dependent tiny ops per step")
static = torch.ones(1024, device=dev)


def step(v):
    for _ in range(200):
        v = v * 1.0001 + 0.0001
    return v


s = torch.cuda.Stream()
s.wait_stream(torch.cuda.current_stream())
with torch.cuda.stream(s):
    step(static)                                         # warm up on a side stream before capture
torch.cuda.current_stream().wait_stream(s)
g = torch.cuda.CUDAGraph()
with torch.cuda.graph(g):
    out = step(static)
torch.cuda.synchronize()


def bench(fn, reps=50):
    fn()
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    for _ in range(reps):
        fn()
    torch.cuda.synchronize()
    return (time.perf_counter() - t0) / reps * 1e3


t_eager = bench(lambda: step(static))
t_graph = bench(g.replay)
ref = step(static)
g.replay()
assert torch.allclose(out, ref)
print(f"  eager: {t_eager:6.3f} ms per step (400 kernel launches)   graph.replay(): {t_graph:6.3f} ms "
      f"({t_eager / t_graph:.1f}x)")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. dispatch keys
  CPU float                  CPU, ADInplaceOrView, AutogradCPU, AutocastCPU
  CPU float, requires_grad   CPU, ADInplaceOrView, AutogradCPU, AutocastCPU
  CUDA float                 CUDA, ADInplaceOrView, AutogradCUDA, AutocastCUDA
  CUDA float, requires_grad  CUDA, ADInplaceOrView, AutogradCUDA, AutocastCUDA
== B. one tiny add (8 elements) on the CPU, us per call
  NumPy a + b                          0.40 us
  torch a + b                          2.03 us
  torch a + b, a.requires_grad         4.08 us
  torch a + b under inference_mode     1.83 us
== C. asynchronous CUDA execution
  2000 tiny kernels: Python returns after   40.1 ms; GPU finishes at   40.2 ms (20.1 us per launch)
  same loop with x[0].item() every step:   68.9 ms (1.7x: no overlap of CPU and GPU)
== D. CUDA Graphs: 200 dependent tiny ops per step
  eager:  5.421 ms per step (400 kernel launches)   graph.replay():  0.703 ms (7.7x)
ALL ASSERTIONS PASSED
```

* An 8-element add costs ~5× more in torch than in NumPy, and ~10× with autograd recording. PyTorch's dispatcher, autograd and allocator layers are built for big tensors. **Element-sized Python loops over tensors are the slow trap.**
* On the GPU, Python returned from 2,000 launches only when the GPU had finished, at ~17–20 µs per launch: the launch rate is the throughput. Adding `.item()` every step cost 1.7–2.0× the time, because the CPU stops running ahead.
* **CUDA Graphs** replayed 400 kernels as one launch, ~7.5–9.2× faster per step (≈ 5.3–6.5 ms → ≈ 0.70 ms). That's the mechanism behind `torch.compile(mode="reduce-overhead")` (06.3). The other fix is fewer, fused kernels.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 | `RuntimeError: view size is not compatible with input tensor's size and stride` | After `transpose`/`permute`/slicing | `view` needs stride-compatible layout | `reshape` (accepts a copy) or `.contiguous().view()` | Know which ops return non-contiguous views |
| F2 🔥 | Memory spikes / OOM in a "metadata only" step | `reshape`/`contiguous`/`flatten` on permuted inputs | Hidden full-size copies | Reorder ops so the copy happens once, or keep the layout the consumer wants | `assert t.is_contiguous()` in hot paths; profiler memory view |
| F3 🔥 | A 1 MB tensor keeps 10 GB of memory alive | `t.untyped_storage().nbytes()` ≫ `t.nbytes` | A slice/view pins the whole storage | `.clone()` the slice you keep | Clone anything cached or returned across module boundaries |
| F4 ⚡ | GPU utilization 20–40 % with small ops | Profiler shows gaps between tiny kernels; CPU busy | Launch-bound: ~17–20 µs per launch here | Batch work, fuse (`torch.compile`), CUDA Graphs | Track kernels per step and step time vs FLOPs |
| F5 ⚡ | Training step stalls every iteration | `cudaMemcpy`/`cudaStreamSynchronize` in the trace | `.item()`, `print(loss)`, `if tensor:`, `nonzero`, boolean masks | Log every N steps; keep values on device; `torch.where` instead of masks | `torch.cuda.set_sync_debug_mode("warn")` in CI runs |
| F6 | Custom CUDA/C++ extension returns garbage | Only for some inputs (after `.T`, slicing) | Kernel assumes contiguous rows; ignores strides/offset | `TORCH_CHECK(t.is_contiguous())` or pass strides | Test extensions with non-contiguous and offset inputs |
| F7 | `RuntimeError: unsupported operation: more than one element of the written-to tensor refers to a single memory location` | In-place op on an `expand`ed tensor | Stride-0 dimension aliases one element | `.clone()` before writing, or use out-of-place ops | Treat expanded tensors as read-only |
| F8 | NumPy array mutated "by itself" | After `torch.from_numpy` | Shared storage by design | `torch.tensor(a)` or `.clone()` to decouple | Name zero-copy bridges explicitly in code review |
| F9 ⚡ | channels_last model no faster | `.contiguous()` calls or format conversions in the trace | Mixed memory formats between layers | Convert model and input once; avoid `.contiguous()` without `memory_format` | Check `is_contiguous(memory_format=torch.channels_last)` at layer boundaries |

**Debugging toolkit.** `t.shape, t.stride(), t.storage_offset(), t.is_contiguous()`; `t.untyped_storage().data_ptr()` and `.nbytes()` (storage identity and size); `torch._C._dispatch_keys(t)`; `torch.cuda.set_sync_debug_mode("warn"|"error")` (flags synchronizing calls); `torch.profiler.profile(activities=[CPU, CUDA], record_shapes=True, profile_memory=True)` with the Chrome trace export to see kernel gaps; `torch.cuda.memory_allocated()` before and after a suspect line to find hidden copies.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "What's the difference between view and reshape?"</b></summary>

**Initial Prompt.** A model fails with `view size is not compatible...` after someone added a `transpose`. The proposed fix replaces every `view` with `reshape`.

**L5 Answer.** "`reshape` is the safe version of `view`; just use it everywhere."

**Why L5 Crashes at Scale.** `reshape` falls back to a full contiguous copy when the strides don't allow a view. On a 2 GB activation that's a silent 2 GB allocation plus a bandwidth-bound copy at ~half of peak (transposing copies ran at ~62–64 GB/s vs ~130–160 GB/s here), every step. It can turn a fitting model into an OOM and nobody sees why.

**L7 Principal Defense.** A tensor is `(storage, offset, sizes, strides)`. `view` is legal only if the new shape can be addressed with strides over the same bytes, and that's why it failed after a transpose. Keep `view` where a copy would be a bug, so the failure is loud. Use `reshape` only where a copy is acceptable, and fix the root cause by choosing the layout the consumer needs once, for example by transposing the weight instead of the activation or using `channels_last` end to end. Verify with `untyped_storage().data_ptr()` and memory deltas, not by reading the code.

</details>

<details><summary><b>Q2 · "Our feature cache uses 40 GB but holds only 2 GB of embeddings. Leak?"</b></summary>

**Initial Prompt.** A service slices rows out of a large embedding table tensor and caches them in a dict.

**L5 Answer.** "Python's GC isn't freeing tensors; call `gc.collect()` and `torch.cuda.empty_cache()`."

**Why L5 Crashes at Scale.** Nothing is garbage. Each cached slice is a view whose `StorageImpl` is the whole table. The refcount on the storage stays above zero as long as any view lives, so the table can never be freed, however many collections run.

**L7 Principal Defense.** Compare `t.nbytes` with `t.untyped_storage().nbytes()` for cached entries. That diagnoses it in one line. Fix by caching `t.clone()` (owning, compact) or by gathering the rows with `index_select`, which allocates exactly the needed bytes. It's the same bug as `String.substring` before JDK 7u6, which shared the parent `char[]`. The policy is that anything crossing a cache or module boundary owns its storage.

</details>

<details><summary><b>Q3 · "The GPU is only 30 % utilized. Should we buy a bigger GPU?"</b></summary>

**Initial Prompt.** A model with many small layers trains at 30 % GPU utilization on an A100.

**L5 Answer.** "Increase the batch size. If it doesn't help, the GPU is too small."

**Why L5 Crashes at Scale.** A bigger GPU makes it worse. If the bottleneck is host-side launch overhead (~17–20 µs per kernel measured here; a few µs on Linux), faster kernels only lengthen the idle gaps. Synchronization points (`.item()` for logging, data-dependent shapes) stop the CPU from queueing work ahead.

**L7 Principal Defense.** Profile first. A trace with short kernels separated by gaps, with the CPU thread busy in Python or the dispatcher, means launch-bound. Then, in order: remove sync points (log every N steps; measured: one `.item()` per step cost 1.7–2.0× loop time); fuse ops with `torch.compile`, which cuts kernel count and memory traffic; capture static parts with CUDA Graphs (`mode="reduce-overhead"`; measured 7.5–9.2× on a 400-kernel step); then increase the per-kernel work (batch size, wider layers). Utilization is an outcome. Track kernels per step and achieved FLOP/s or bandwidth against the roofline.

</details>

<details><summary><b>Q4 · "Why does `inference_mode` exist if we have `no_grad`?"</b></summary>

**Initial Prompt.** Explain the difference for a high-QPS inference service.

**L5 Answer.** "They're the same; `inference_mode` is just newer."

**Why L5 Crashes at Scale.** At high QPS with many small ops, per-op overhead is the cost. Under `no_grad`, the autograd and `ADInplaceOrView` dispatcher layers still run: they check, find no grad needed, and still maintain version counters and view metadata.

**L7 Principal Defense.** Every float tensor carries `AutogradCPU/CUDA` and `ADInplaceOrView` in its key set (measured, even without `requires_grad`). `inference_mode` adds those keys to the thread-local **excluded** set, so the dispatcher skips the layers entirely, and tensors created inside are inference tensors without version counters. Measured for a tiny CPU add: ~1.9–2.2 µs against ~2.1–2.5 µs plain and ~4.0–4.6 µs with recording. The trade-off: inference tensors can't later be used in autograd-recorded computations, which is correct for serving. Use `inference_mode` in serving paths, `no_grad` in training-time evaluation that may mix with grad-tracked tensors.

</details>

<details><summary><b>Q5 · "How does PyTorch decide which kernel runs for `a + b`?"</b></summary>

**Initial Prompt.** Walk through the call path at the C++ level.

**L5 Answer.** "It checks the device and calls the CUDA kernel."

**Why L5 Crashes at Scale.** That model can't explain autocast, functionalization for `torch.compile`, `__torch_dispatch__` subclasses (FSDP2's `DTensor`, fake tensors for compilation), or why a custom op breaks under autocast. All of those are dispatcher layers.

**L7 Principal Defense.** The generated Python binding parses arguments, then `Dispatcher::call` looks up the operator's kernel table. It computes a `DispatchKeySet` from the union of the inputs' key sets plus thread-local include/exclude sets, then takes the highest-priority key. Typical order: Python/`Functionalize`/`PreDispatch` modes → `AutocastCUDA` → `AutogradCUDA` → `ADInplaceOrView` → `CUDA`. Each layer does its part and **redispatches** with its own key masked off. Adding a capability means registering a kernel for a key. That's how `DTensor`, `FakeTensor` and vmap compose without changing operator code. It's the visitor/decorator pattern implemented as a bitset-indexed vtable.

</details>

<details><summary><b>Q6 · "Why is the transposing copy half the speed of a normal copy?"</b></summary>

**Initial Prompt.** `x.T.contiguous()` on 64 MiB took 2.1 ms; `x.clone()` took 0.95–1.0 ms.

**L5 Answer.** "Transposes are just more complex."

**Why L5 Crashes at Scale.** Without the memory model you can't predict which layout transformations are cheap, and models with many permutes (attention heads, NHWC↔NCHW) lose 2× bandwidth on each one.

**L7 Principal Defense.** GPU DRAM is accessed in 32-byte sectors per warp request. A warp of 32 threads reading consecutive floats uses every byte it fetches (coalesced). In a transposing copy one side is strided: consecutive threads touch addresses 16 KiB apart (stride 4096 × 4 B), so each 4-byte access drags in a 32-byte sector, and only cache reuse recovers some of it. PyTorch's copy kernel tiles through shared memory to coalesce both sides partially, but it still measured ~62–64 GB/s vs ~130–160 GB/s. Plan layouts so permutes happen once (preprocessing, weight transposes at load time), and let `torch.compile` fold them into consumers.

</details>

<details><summary><b>Q7 · "When can't we use CUDA Graphs?"</b></summary>

**Initial Prompt.** CUDA Graphs gave 7.5–9.2× on a microbenchmark. Turn them on for the production model.

**L5 Answer.** "Wrap the training step in `torch.cuda.graph` and replay it."

**Why L5 Crashes at Scale.** A graph freezes kernel arguments: device pointers, shapes, scalar values. Any Python control flow that depends on data, any CPU sync inside the region, dynamic shapes (variable sequence lengths), allocations whose addresses change, or RNG without graph-safe handling will give wrong results or capture errors. Optimizers that change hyperparameters on the CPU side also break.

**L7 Principal Defense.** Use graphs for the static core: fixed shapes (bucket and pad sequence lengths into a few sizes, one graph per bucket), static input buffers you `copy_` into, warm-up on a side stream before capture (the listing does), and a private memory pool. Prefer `torch.compile(mode="reduce-overhead")`, which handles pools, falls back on dynamic shapes, and re-records when needed. Measure memory too, because each graph pins its pool. The win is largest exactly where launch overhead dominates: small batches, decode loops, many small layers.

</details>

<details><summary><b>Q8 · "Port this NumPy stride trick to PyTorch."</b></summary>

**Initial Prompt.** A sliding-window feature extractor uses `np.lib.stride_tricks.as_strided` with byte strides; port it to torch for GPU execution.

**L5 Answer.** "Call `torch.as_strided` with the same arguments."

**Why L5 Crashes at Scale.** NumPy strides are **bytes**, PyTorch strides are **elements**. The same numbers index 4× or 8× too far, reading out of bounds of the logical tensor (or garbage within the storage) without any error.

**L7 Principal Defense.** Prefer `Tensor.unfold(dim, size, step)`, which builds the strided window view for you, and verify with `stride()` and a small reference. If `as_strided` is needed, convert strides by dividing by `itemsize` and account for `storage_offset`. Windows created this way overlap in memory, so treat them as read-only (F7). For cross-library handoff, use DLPack (`torch.from_dlpack`, `np.from_dlpack`), which carries strides explicitly. It's zero-copy here and the address check is in the listing.

</details>

<details><summary><b>Q9 · "Design a tensor type for a JVM service."</b></summary>

**Initial Prompt.** A Java feature-serving system needs n-dimensional arrays to pass to an ONNX/LibTorch runtime without copies.

**L5 Answer.** "Use `float[][]` arrays and convert at the boundary."

**Why L5 Crashes at Scale.** Nested Java arrays are arrays of pointers to separately allocated rows: not contiguous, GC-movable, and every native call needs a full copy (or pinning). At thousands of requests per second the copies and GC pressure dominate.

**L7 Principal Defense.** Copy PyTorch's split. Use an immutable header record `(MemorySegment storage, long offset, long[] sizes, long[] strides, dtype, device)` over off-heap memory from the FFM API (`Arena`, `MemorySegment`, Java 22+), with views created by header arithmetic. Pass `MemorySegment.address()` plus shape and strides to native runtimes, or export DLPack/Arrow structs, so there's no copy. Lifetime is explicit (`Arena` scopes) instead of relying on GC, which also avoids the "slice pins the buffer" leak by making ownership visible. That's what ONNX Runtime's Java `OnnxTensor` over direct buffers approximates.

</details>

---

## 5. Invariants Checklist

- [ ] A tensor is `(storage, storage_offset, sizes, strides, dtype, device)` plus autograd metadata. Views share storage and the version counter.
- [ ] `view` never copies and fails if strides can't express the shape. `reshape`/`contiguous` may allocate and copy.
- [ ] PyTorch strides are in elements; NumPy strides are in bytes.
- [ ] A view keeps its entire storage alive. Clone what you cache.
- [ ] Every op passes through the dispatcher: key set → highest-priority layer → redispatch. `inference_mode` removes layers; `no_grad` only disables recording.
- [ ] CUDA ops are asynchronous. `.item()`, `.cpu()`, printing, data-dependent shapes and `if t:` synchronize.
- [ ] Small ops are launch-bound (~17–20 µs per launch on this Windows host). Fuse, batch, or capture with CUDA Graphs.
- [ ] Layout matters for bandwidth: transposing copies ran at ~half the speed of straight copies, and channels_last convolutions ran ~1.4× faster in fp16.

---

## 6. References

- PyTorch `TensorImpl.h` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/c10/core/TensorImpl.h
- PyTorch `StorageImpl.h` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/c10/core/StorageImpl.h
- PyTorch `DispatchKey.h` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/c10/core/DispatchKey.h
- E. Yang, "PyTorch internals" (strides, dispatch, autograd) — http://blog.ezyang.com/2019/05/pytorch-internals/
- E. Yang, "Let's talk about the PyTorch dispatcher" — http://blog.ezyang.com/2020/09/lets-talk-about-the-pytorch-dispatcher/
- PyTorch docs: tensor views — https://docs.pytorch.org/docs/stable/tensor_view.html
- PyTorch docs: inference mode — https://docs.pytorch.org/docs/stable/generated/torch.autograd.grad_mode.inference_mode.html
- PyTorch docs: CUDA semantics (asynchronous execution, CUDA Graphs) — https://docs.pytorch.org/docs/stable/notes/cuda.html
- PyTorch tutorial: channels last memory format — https://docs.pytorch.org/tutorials/intermediate/memory_format_tutorial.html
- DLPack specification — https://dmlc.github.io/dlpack/latest/
- NVIDIA CUDA C++ Best Practices Guide (coalesced access) — https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/
