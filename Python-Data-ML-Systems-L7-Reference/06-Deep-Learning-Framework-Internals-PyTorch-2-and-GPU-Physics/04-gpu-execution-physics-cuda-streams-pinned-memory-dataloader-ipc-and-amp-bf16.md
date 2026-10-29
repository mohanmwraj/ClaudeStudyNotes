# 06.4 · GPU Execution Physics: CUDA Streams, Pinned Memory, DataLoader IPC & AMP/bf16

> **Folder 06 · Deep Learning Framework Internals: PyTorch 2 & GPU Physics**
> **Measured on:** PyTorch 2.14.1+cu130, NVIDIA GeForce RTX 3050 Laptop GPU (Ampere GA107, sm_86, 16 SMs, 4 GB GDDR6, 3rd-generation tensor cores, driver 610.78, WDDM), i5-11260H (6C/12T), 16 GB RAM, Windows 11, CPython 3.14.5 (`spawn` start method), psutil 7.2.2.
> **Source quoted:** `torch/include/c10/core/AllocatorConfig.h`, `torch/amp/grad_scaler.py`, `torch/utils/data/dataloader.py` from the installed wheel (tag `v2.14.1`).

---

## 0. Orientation & the JVM/C++ Bridge

A GPU training step is a pipeline across three processors. CPU workers decode and collate samples, a DMA engine moves bytes over PCIe, and the SMs compute. It's fast only when these overlap. This file measures the four mechanisms that decide whether they do: **page-locked memory** (whether the DMA engine can run asynchronously), **streams and events** (whether copies and kernels can run concurrently), **DataLoader worker processes** (how much CPU parallelism costs in startup time and RAM), and **number formats** (how many bytes and tensor-core FLOPs each value costs). It ends with the **caching allocator**, which decides whether "free" GPU memory is usable.

| GPU concept | JVM analogue | C/C++ analogue |
|---|---|---|
| pinned (page-locked) host memory | `ByteBuffer.allocateDirect`: off-heap, never moved by GC | `mlock`ed buffer / `cudaHostAlloc` |
| pageable → staging copy | heap `byte[]` copied to a native buffer before a JNI/NIO write | bounce buffers in a driver |
| CUDA stream / event | an ordered executor queue / a `CompletableFuture` another queue waits on | per-queue FIFO + fences |
| DataLoader workers + `prefetch_factor` | a producer pool feeding a bounded `BlockingQueue` | worker processes + ring buffer in shared memory |
| `spawn` worker start | launching a fresh JVM per worker (class loading, JIT warm-up) | `fork`+`exec` |
| `fork` + refcount CoW | — (no analogue: JVM headers aren't written on read) | CoW pages dirtied by writes to "read-only" data |
| caching allocator: reserved vs allocated | heap committed vs used; G1 rarely uncommits | a slab/arena allocator that keeps freed blocks |
| fp16 / bf16 / tf32 | `float` vs `double`; no 16-bit arithmetic type, only conversions (`Float.floatToFloat16`, JDK 20+) | `_Float16`, `__nv_bfloat16` |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 Host → device: why pinned memory matters

```text
 pageable source (malloc'd, the OS may page it out or move the physical frames):
   CPU: memcpy chunk → driver's pinned staging buffer ─► DMA chunk ─► GPU      (repeat; CPU busy throughout)
   the call cannot return until the CPU has copied every chunk: .to(non_blocking=True) is effectively synchronous
 pinned source (cudaHostAlloc / tensor.pin_memory(): physical pages locked, the DMA engine reads them directly):
   CPU: enqueue one DMA descriptor, return                                   ─► DMA engine ─► GPU
   the CPU is free in ~0.1 ms; the copy completes in the stream's order, overlapping CPU work and other streams
```

Measured for 256 MiB: H2D from pinned memory ran at **~9.8–12.5 GB/s** and from pageable at ~7–10 GB/s. ⚠ That's only 1.1–1.7× on this Windows/WDDM host, consistent with a PCIe 4.0 ×8 link (15.75 GB/s raw); the link width wasn't queried. The decisive difference is **blocking**: `.to(cuda, non_blocking=True)` returned after **~0.07–0.09 ms** from pinned memory and after **~32–42 ms**, the whole copy, from pageable memory. Pinned memory is what makes `non_blocking` mean anything.

### 1.2 Streams, events, and the copy engine

```text
 one stream (FIFO):   [copy 0][mm mm][copy 1][mm mm][copy 2][mm mm] ...        time = Σ copies + Σ compute
 two streams + events:
   copy stream:      [copy 0][copy 1][copy 2][copy 3] ...       (DMA engine)
   compute stream:          [mm mm  ][mm mm  ][mm mm  ] ...     (SMs)   wait_event(copy i) before compute i
                                                               time ≈ first copy + Σ compute (if compute ≥ copy)
 allocator safety: a block belongs to the stream that allocated it. If another stream uses it, call
   tensor.record_stream(other) so the block isn't reused before that stream's queued work completes.
```

The GPU has separate copy engines, so a DMA transfer and kernels on different streams can run at the same time. The default stream would serialize them.

### 1.3 DataLoader: processes, queues, and shared memory

```text
 main process                                      worker k (one process each)
   sampler → batches of indices ── index_queue[k] ──►  dataset[i] for i in batch → collate_fn → tensors
                                                       tensors moved to shared memory (Linux: file descriptors in
                                                       /dev/shm; Windows: named file mappings)
   ◄──────────────── data_queue (handles only, not bytes) ─┘
   pin_memory thread: copy each batch into pinned host memory (if pin_memory=True)
   your loop: batch.to(device, non_blocking=True)
 in flight: prefetch_factor (default 2) batches per worker; persistent_workers=False (default) re-creates the
            workers for every epoch (dataloader.py)
```

**Start methods decide the memory model.**

```text
 fork (Linux default): workers start instantly, sharing the parent's pages copy-on-write.
   CPython writes to every object it touches (ob_refcnt += 1). Reading a list of 10M Python objects in a worker
   dirties every page holding those objects → each worker gradually gets a private copy. ⚠ not executable here;
   this is pytorch/pytorch#13246, the "DataLoader memory leak" that isn't a leak.
 spawn (Windows, macOS default): a fresh interpreter per worker re-imports torch and unpickles the dataset.
   Measured: ~2.5–3.9 s to first batch, ~386–390 MiB USS per worker just for the runtime, plus a full private
   copy of any Python-object dataset.
 both: store data as a few large buffers (NumPy, Arrow, memory-mapped files). Buffers have one refcount per
   array, not per row, and memory-mapped files are shared through the OS page cache.
```

### 1.4 Number formats and tensor cores

```text
            sign exp mantissa   max          smallest normal   eps (2^-mantissa)
 fp32        1    8    23       3.4e38        1.2e-38           1.2e-7
 tf32        1    8    10      (fp32 range; used inside tensor-core multiplies, storage stays fp32)
 fp16        1    5    10       65504         6.1e-5            9.8e-4     ← overflow and underflow risk
 bf16        1    8     7       3.4e38        1.2e-38           7.8e-3     ← fp32 range, coarse precision
```

**Autocast** is a dispatcher layer (`AutocastCUDA`, 06.1). Per-op policy lists send matmul, conv and linear to fp16/bf16, keep softmax, log, exp, reductions, norms and losses in fp32, and promote mixed inputs for the rest. Weights stay fp32 ("master weights"), and their low-precision casts are cached inside the autocast region. **Loss scaling** (fp16 only) multiplies the loss by S so small gradients survive fp16's range, unscales before the optimizer step, and skips the step if any gradient is inf/NaN. Defaults in `torch/amp/grad_scaler.py`: `init_scale = 2**16`, `growth_factor = 2.0`, `backoff_factor = 0.5`, `growth_interval = 2000`. bf16 has fp32's exponent range and needs no scaler, but its 8-bit precision means **accumulation must be fp32**. Library kernels do this, and hand-written loops often don't.

### 1.5 The CUDA caching allocator

```text
 constants (c10/core/AllocatorConfig.h): every size rounded to ≥ 512 B (kMinBlockSize)
   ≤ 1 MiB (kSmallSize)          small pool, carved from 2 MiB segments (kSmallBuffer)
   1–10 MiB (kMinLargeAlloc)     large pool, carved from 20 MiB segments (measured: segment sizes [2, 20])
   > 10 MiB                      own segment, rounded up to 2 MiB (kRoundLarge)
 malloc(size, stream): best-fit free block of this stream's pool (split if larger)
    → else cudaMalloc a new segment
    → else free every cached segment with no live blocks (cudaFree; synchronizes), retry   [num_alloc_retries]
    → else OutOfMemoryError ("... X is reserved by PyTorch but unallocated ...")
 free(block): back to the pool (merged with free neighbours in the same segment); never returned to the driver
              until empty_cache() — and only segments with NO live block can be returned
 expandable_segments:True: one virtual address range per stream, physical memory mapped in 2 MiB pages
              (cuMemCreate/cuMemMap) and grown at the end, instead of one cudaMalloc per segment
```

`memory_allocated()` counts live tensors and `memory_reserved()` counts everything the allocator holds. `nvidia-smi` shows reserved plus the CUDA context (hundreds of MiB), so it always looks fuller than your tensors.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Pinned memory, `non_blocking`, streams and the async-D2H race

```python
"""h2d_pinned_streams.py - host <-> device copies: pageable vs pinned memory, non_blocking, streams, overlap.

A: H2D/D2H bandwidth for 256 MiB from pageable vs page-locked (pinned) host memory.
B: what non_blocking=True really does: from pageable memory the CPU still waits (staging copy); from pinned it returns.
C: overlap: 8 chunks of (copy in -> 2 matmuls) on one stream vs a copy stream + compute stream with events.
D: the async D2H trap: the copy is still in flight when the call returns; reading before synchronizing is a race.
"""
import time

import torch

dev = torch.device("cuda")
torch.manual_seed(0)
N = 64 * 2**20                                           # 64M float32 = 256 MiB
pageable = torch.randn(N)
pinned = pageable.pin_memory()
assert pinned.is_pinned() and not pageable.is_pinned()
dst = torch.empty(N, device=dev)


def gpu_ms(fn, reps=5):
    fn()
    torch.cuda.synchronize()
    a, b = torch.cuda.Event(enable_timing=True), torch.cuda.Event(enable_timing=True)
    a.record()
    for _ in range(reps):
        fn()
    b.record()
    torch.cuda.synchronize()
    return a.elapsed_time(b) / reps


print("== A. copy bandwidth, 256 MiB")
gb = N * 4 / 1e9
host_back = torch.empty(N).pin_memory()
host_page = torch.empty(N)
rows = [("H2D from pageable", lambda: dst.copy_(pageable)), ("H2D from pinned", lambda: dst.copy_(pinned, non_blocking=True)),
        ("D2H to pageable", lambda: host_page.copy_(dst)), ("D2H to pinned", lambda: host_back.copy_(dst, non_blocking=True))]
bw = {}
for label, fn in rows:
    ms = gpu_ms(fn)
    bw[label] = gb / (ms / 1e3)
    print(f"  {label:20} {ms:7.2f} ms  {bw[label]:5.1f} GB/s")

print("== B. how long the CPU is blocked by .to(device, non_blocking=True)")
blocked = {}
for label, src in (("pageable source", pageable), ("pinned source", pinned)):
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    out = src.to(dev, non_blocking=True)
    t_call = time.perf_counter() - t0
    torch.cuda.synchronize()
    t_done = time.perf_counter() - t0
    print(f"  {label:16} call returns after {t_call * 1e3:6.2f} ms; copy complete at {t_done * 1e3:6.2f} ms")
    blocked[label] = t_call / t_done
    del out
assert blocked["pinned source"] < 0.1 and blocked["pageable source"] > 0.9

print("== C. overlapping copies with compute: 8 chunks of 32 MiB, each followed by 2 matmuls (2048^2)")
chunks = [torch.randn(8 * 2**20).pin_memory() for _ in range(8)]
w = torch.randn(2048, 2048, device=dev)
bufs = [torch.empty(8 * 2**20, device=dev) for _ in range(8)]


def compute(buf):
    m = buf[: 2048 * 2048].view(2048, 2048)
    for _ in range(2):
        m = m @ w * 1e-3
    return m.sum()


def serial():
    return sum(compute(bufs[i].copy_(chunks[i], non_blocking=True)) for i in range(8))


copy_stream = torch.cuda.Stream()


def overlapped():
    events = []
    with torch.cuda.stream(copy_stream):                 # all copies on their own stream: DMA engine runs ahead
        for i in range(8):
            bufs[i].copy_(chunks[i], non_blocking=True)
            ev = torch.cuda.Event()
            ev.record(copy_stream)
            events.append(ev)
    total = 0
    for i in range(8):
        torch.cuda.current_stream().wait_event(events[i])   # compute on chunk i waits only for copy i
        total = total + compute(bufs[i])
    for b in bufs:
        b.record_stream(torch.cuda.current_stream())     # tell the allocator the compute stream uses these buffers
    return total


ref = serial()
assert torch.allclose(ref, overlapped(), rtol=1e-3)
t_copy = gpu_ms(lambda: [bufs[i].copy_(chunks[i], non_blocking=True) for i in range(8)])
t_comp = gpu_ms(lambda: [compute(bufs[i]) for i in range(8)])
t_ser, t_ovl = gpu_ms(serial), gpu_ms(overlapped)
print(f"  copies alone {t_copy:6.2f} ms, compute alone {t_comp:6.2f} ms, sum {t_copy + t_comp:6.2f} ms")
print(f"  one stream   {t_ser:6.2f} ms")
print(f"  two streams  {t_ovl:6.2f} ms  (hides {(t_ser - t_ovl) / t_copy * 100:3.0f}% of the copy time)")

print("== D. asynchronous D2H: the call returns before the bytes arrive")
src = torch.full((N,), 7.0, device=dev)
out = torch.zeros(N).pin_memory()
out.copy_(src, non_blocking=True)
in_flight = not torch.cuda.current_stream().query()
print(f"  right after copy_(non_blocking=True): stream idle = {not in_flight}; "
      f"reading out now would race the DMA engine")
done = torch.cuda.Event()
done.record()
done.synchronize()                                       # or torch.cuda.synchronize() / stream.synchronize()
print(f"  after event.synchronize(): out[-1] = {out[-1].item()}")
assert in_flight and out[-1].item() == 7.0
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. copy bandwidth, 256 MiB
  H2D from pageable      25.42 ms   10.6 GB/s
  H2D from pinned        21.67 ms   12.4 GB/s
  D2H to pageable        26.40 ms   10.2 GB/s
  D2H to pinned          20.78 ms   12.9 GB/s
== B. how long the CPU is blocked by .to(device, non_blocking=True)
  pageable source  call returns after  31.66 ms; copy complete at  31.72 ms
  pinned source    call returns after   0.07 ms; copy complete at  21.40 ms
== C. overlapping copies with compute: 8 chunks of 32 MiB, each followed by 2 matmuls (2048^2)
  copies alone  21.46 ms, compute alone  89.02 ms, sum 110.48 ms
  one stream   105.56 ms
  two streams   90.16 ms  (hides  72% of the copy time)
== D. asynchronous D2H: the call returns before the bytes arrive
  right after copy_(non_blocking=True): stream idle = False; reading out now would race the DMA engine
  after event.synchronize(): out[-1] = 7.0
ALL ASSERTIONS PASSED
```

* Pinned beat pageable bandwidth by only 1.1–1.7× here (§1.1), but pinned memory made the CPU **free in ~0.1 ms instead of blocked for the full ~32–42 ms copy**. That's the property the DataLoader's `pin_memory=True` exists for.
* With copies on their own stream and per-chunk events, the pipeline took about as long as compute alone. **The second stream hid ~72–107 % of the copy time.** (Over 100 % means the single-stream version also paid serialization bubbles.) On one stream, time ≈ copies + compute.
* **D** is the race behind "my host tensor is all zeros": a `non_blocking` D2H copy is still in flight when the call returns. Synchronize on an event (or the stream) before reading.
* ⚠ Absolute times in this file varied by up to ~1.7× between runs. The laptop GPU throttles (84 °C observed; SM clock down from a 2.1 GHz maximum), so compare rows within one run.

### 2.2 DataLoader under `spawn`: startup, persistence, per-worker memory, pinning

```python
"""dataloader_workers.py - DataLoader physics under the spawn start method (Windows/macOS default): workers, startup, memory.

A: a CPU-bound decode (~0.5 ms per sample) feeding batches of 64: num_workers 0 / 2 / 4 (persistent), startup vs warm epoch.
B: persistent_workers: without it every epoch re-spawns the workers (re-import torch, re-unpickle the dataset).
C: what each worker holds: a dataset backed by a list of 500k Python tuples vs the same data in NumPy arrays:
   bytes pickled to every spawned worker, and each worker's unique memory (USS, psutil).
D: pin_memory=True: batches arrive page-locked, so .to(device, non_blocking=True) returns immediately.
Everything that runs at import time also runs in every worker: the work lives under `if __name__ == "__main__":`.
"""
import pickle
import time

import numpy as np
import psutil
import torch
from torch.utils.data import DataLoader, Dataset


class Decode(Dataset):
    def __init__(self, n):
        self.n = n

    def __len__(self):
        return self.n

    def __getitem__(self, i):
        a = np.random.default_rng(i).standard_normal(16384, dtype=np.float32)
        for _ in range(12):                              # stand-in for JPEG decode / augmentation
            a = np.tanh(a * 1.01)
        return torch.from_numpy(a), i % 10


class ListBacked(Dataset):
    def __init__(self, n):
        self.rows = [(i, float(i) * 0.5) for i in range(n)]

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, i):
        k, v = self.rows[i]
        return torch.tensor([v]), k


class ArrayBacked(Dataset):
    def __init__(self, n):
        self.keys = np.arange(n, dtype=np.int64)
        self.vals = np.arange(n, dtype=np.float64) * 0.5

    def __len__(self):
        return len(self.keys)

    def __getitem__(self, i):
        return torch.tensor([self.vals[i]]), int(self.keys[i])


def epoch_times(loader, epochs=2):
    out, first = [], None
    for _ in range(epochs):
        t0 = time.perf_counter()
        for j, (xb, _) in enumerate(loader):
            if first is None and j == 0:
                first = time.perf_counter() - t0
        out.append(time.perf_counter() - t0)
    return first, out


def worker_uss(loader):
    it = iter(loader)
    next(it)                                             # workers are up and have unpickled the dataset
    kids = psutil.Process().children()
    uss = [k.memory_full_info().uss / 2**20 for k in kids]
    del it
    return uss


if __name__ == "__main__":
    print(f"start method: {torch.multiprocessing.get_start_method()}, logical CPUs: {psutil.cpu_count()}")
    ds = Decode(4096)
    t0 = time.perf_counter()
    for i in range(64):
        ds[i]
    per = (time.perf_counter() - t0) / 64
    print(f"== A. decode cost {per * 1e3:.2f} ms per sample (first 64, cold); 4096 samples per epoch, batch 64")
    res = {}
    for nw in (0, 2, 4):
        first, (e1, e2) = epoch_times(DataLoader(ds, batch_size=64, num_workers=nw, persistent_workers=nw > 0))
        res[nw] = e2
        print(f"  num_workers={nw}  first batch after {first:5.2f} s   epoch 1 {e1:5.2f} s   warm epoch 2 {e2:5.2f} s "
              f"({res[0] / e2:3.1f}x)")
    assert res[4] < res[0] / 2

    print("== B. persistent_workers (num_workers=4)")
    for pw in (False, True):
        _, (e1, e2) = epoch_times(DataLoader(ds, batch_size=64, num_workers=4, persistent_workers=pw), epochs=2)
        print(f"  persistent_workers={pw!s:5}  epoch 1 {e1:5.2f} s   epoch 2 {e2:5.2f} s")

    print("== C. per-worker memory: 500k rows as Python tuples vs NumPy arrays (num_workers=2)")
    for label, cls in (("list of tuples", ListBacked), ("NumPy arrays", ArrayBacked)):
        d = cls(500_000)
        size = len(pickle.dumps(d, protocol=pickle.HIGHEST_PROTOCOL))
        uss = worker_uss(DataLoader(d, batch_size=256, num_workers=2, persistent_workers=True))
        print(f"  {label:15} pickled to each worker {size / 2**20:6.1f} MiB   worker USS "
              f"{', '.join(f'{u:5.0f} MiB' for u in uss)}")

    print("== D. pin_memory=True")
    dev = torch.device("cuda")
    for pin in (False, True):
        xb, _ = next(iter(DataLoader(ds, batch_size=64, num_workers=0, pin_memory=pin)))
        torch.cuda.synchronize()
        t0 = time.perf_counter()
        xd = xb.to(dev, non_blocking=True)
        t_call = time.perf_counter() - t0
        torch.cuda.synchronize()
        print(f"  pin_memory={pin!s:5}  batch.is_pinned()={xb.is_pinned()!s:5}  "
              f".to(cuda, non_blocking=True) returned after {t_call * 1e3:5.2f} ms ({xb.numel() * 4 / 2**20:.0f} MiB)")
        assert xb.is_pinned() == pin
    print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
start method: spawn, logical CPUs: 12
== A. decode cost 0.76 ms per sample (first 64, cold); 4096 samples per epoch, batch 64
  num_workers=0  first batch after  0.03 s   epoch 1  2.10 s   warm epoch 2  2.06 s (1.0x)
  num_workers=2  first batch after  2.59 s   epoch 1  3.78 s   warm epoch 2  1.19 s (1.7x)
  num_workers=4  first batch after  2.85 s   epoch 1  3.64 s   warm epoch 2  0.79 s (2.6x)
== B. persistent_workers (num_workers=4)
  persistent_workers=False  epoch 1  4.37 s   epoch 2  4.28 s
  persistent_workers=True   epoch 1  3.86 s   epoch 2  0.88 s
== C. per-worker memory: 500k rows as Python tuples vs NumPy arrays (num_workers=2)
  list of tuples  pickled to each worker    7.5 MiB   worker USS   444 MiB,   447 MiB
  NumPy arrays    pickled to each worker    7.6 MiB   worker USS   386 MiB,   386 MiB
== D. pin_memory=True
  pin_memory=False  batch.is_pinned()=False  .to(cuda, non_blocking=True) returned after  1.94 ms (4 MiB)
  pin_memory=True   batch.is_pinned()=True   .to(cuda, non_blocking=True) returned after  0.09 ms (4 MiB)
ALL ASSERTIONS PASSED
```

* Warm epochs scaled with workers (~1.7–1.8× with 2, ~2.6–3.0× with 4). The first batch arrived only after **~2.5–3.9 s** of spawn and import time, slower than the whole single-process epoch (~2.1–2.8 s).
* **Without `persistent_workers`, every epoch pays the spawn again**: ~4.2–5.6 s per epoch vs ~0.7–1.0 s with persistent workers. For short epochs (validation, small datasets) the default is a pessimization.
* **Pickled size isn't memory size.** Both datasets pickled to ~7.5 MiB, but the list of 500k tuples cost each worker **~58–62 MiB more USS** once unpickled into Python objects (tuple + int + float per row). The NumPy version added nothing measurable. Every spawned worker also costs ~386 MiB just for the runtime, so 8 workers are ~3 GB of host RAM before any data.
* `pin_memory=True` delivered page-locked batches, and the following `.to(cuda, non_blocking=True)` returned in ~0.09–0.14 ms instead of ~1.9–2.3 ms for 4 MiB.

### 2.3 Mixed precision: throughput, failure modes, and a real training run

```python
"""amp_mixed_precision.py - number formats on tensor cores: fp32, tf32, fp16, bf16; overflow, underflow, loss scaling.

A: the formats: exponent/mantissa bits, max, smallest normal, machine epsilon (torch.finfo).
B: matmul throughput (4096^3) in fp32, tf32, fp16 and bf16, and the error of each against a float64 reference.
C: failure modes: fp16 overflow past 65504; bf16 rounding (256 + 1 == 256); fp16 gradient underflow fixed by scaling.
D: a training run (MLP regression): fp32 vs autocast fp16 + GradScaler vs autocast bf16 - step time and final loss.
"""
import time

import torch

dev = torch.device("cuda")
torch.manual_seed(0)
print(f"device: {torch.cuda.get_device_name(0)}, compute capability {torch.cuda.get_device_capability(0)}, "
      f"bf16 supported: {torch.cuda.is_bf16_supported()}")

print("== A. formats")
bits = {torch.float32: (8, 23), torch.float16: (5, 10), torch.bfloat16: (8, 7)}
for dt, (e, m) in bits.items():
    fi = torch.finfo(dt)
    print(f"  {str(dt):15} 1+{e}+{m:<2} bits  max {fi.max:10.4g}  smallest normal {fi.tiny:10.4g}  eps {fi.eps:9.3g}")
print("  tf32 = fp32 range (8-bit exponent) with a 10-bit mantissa inside the tensor-core multiply; storage stays fp32")


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


print("== B. 4096 x 4096 x 4096 matmul")
n = 4096
a64, b64 = torch.randn(n, n, device=dev, dtype=torch.float64), torch.randn(n, n, device=dev, dtype=torch.float64)
ref = (a64[:256] @ b64)                                  # float64 reference for the first 256 rows
flops = 2 * n ** 3
tput = {}
for label, dt, tf32 in (("fp32 (no tf32)", torch.float32, False), ("tf32", torch.float32, True),
                        ("fp16", torch.float16, False), ("bf16", torch.bfloat16, False)):
    torch.backends.cuda.matmul.allow_tf32 = tf32
    a, b = a64.to(dt), b64.to(dt)
    ms = gpu_ms(lambda: a @ b)
    err = ((a[:256] @ b).double() - ref).abs().max().item() / ref.abs().max().item()
    tput[label] = flops / (ms / 1e3) / 1e12
    print(f"  {label:15} {ms:7.2f} ms  {tput[label]:5.1f} TFLOP/s   max rel. error vs fp64 {err:8.1e}")
    del a, b
torch.backends.cuda.matmul.allow_tf32 = False
del a64, b64, ref
assert tput["fp16"] > 2 * tput["fp32 (no tf32)"]

print("== C. failure modes")
big = torch.tensor([60000.0, 70000.0])
print(f"  fp16 overflow: {big.tolist()} -> {big.half().tolist()};  300 * 300 in fp16 = "
      f"{(torch.tensor(300.0).half() * torch.tensor(300.0).half()).item()}")
acc = torch.tensor(0.0, dtype=torch.bfloat16)
for _ in range(1000):
    acc = acc + 1                                        # a bf16 accumulator: every partial sum is rounded to 8 bits
print(f"  bf16 rounding: 256 + 1 = {(torch.tensor(256.0, dtype=torch.bfloat16) + 1).item()}; 1000 sequential bf16 "
      f"additions of 1.0 = {acc.item():.0f}; torch.ones(1000, dtype=bfloat16).sum() = "
      f"{torch.ones(1000, dtype=torch.bfloat16).sum().item():.0f} (the kernel accumulates in fp32)")
assert acc.item() == 256
x = torch.randn(2048, 2048, device=dev)
w = torch.randn(2048, 2048, device=dev, requires_grad=True)
for scale in (1.0, 65536.0):
    w.grad = None
    with torch.autocast("cuda", dtype=torch.float16):
        out = x @ w                                      # fp16 output; its gradient is computed in fp16
    loss = out.float().mean() * 1e-3 * scale             # grad per output element = 1e-3 * scale / 4M
    loss.backward()
    g = w.grad / scale
    print(f"  fp16 backward, loss scale {scale:7.0f}: zero gradient entries {(g == 0).float().mean().item() * 100:5.1f}%  "
          f"mean |grad| {g.abs().mean().item():.3e}")
assert (g == 0).float().mean().item() < 0.01

print("== D. 300 training steps, 6-layer MLP width 2048, batch 1024")


def train(mode):
    torch.manual_seed(1)
    model = torch.nn.Sequential(*[m for _ in range(6) for m in (torch.nn.Linear(2048, 2048), torch.nn.GELU())],
                                torch.nn.Linear(2048, 1)).to(dev)
    opt = torch.optim.AdamW(model.parameters(), lr=3e-4)
    scaler = torch.amp.GradScaler("cuda", enabled=(mode == "fp16"))
    gen = torch.Generator(device=dev).manual_seed(2)
    wt = torch.randn(2048, 1, device=dev, generator=gen) / 45
    dt = {"fp16": torch.float16, "bf16": torch.bfloat16}.get(mode)
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    for step in range(300):
        xb = torch.randn(1024, 2048, device=dev, generator=gen)
        yb = torch.tanh(xb @ wt)
        with torch.autocast("cuda", dtype=dt or torch.float32, enabled=dt is not None):
            loss = torch.nn.functional.mse_loss(model(xb).float(), yb)
        opt.zero_grad(set_to_none=True)
        scaler.scale(loss).backward()
        scaler.step(opt)
        scaler.update()
    torch.cuda.synchronize()
    return (time.perf_counter() - t0) / 300 * 1e3, loss.item(), scaler.get_scale() if mode == "fp16" else None


res = {}
for mode in ("fp32", "fp16", "bf16"):
    ms, loss, sc = train(mode)
    res[mode] = (ms, loss)
    extra = f"   final GradScaler scale {sc:.0f}" if sc is not None else ""
    label = {"fp32": "fp32", "fp16": "autocast fp16 + GradScaler", "bf16": "autocast bf16 (no scaler)"}[mode]
    print(f"  {label:28} {ms:6.2f} ms/step ({res['fp32'][0] / ms:3.1f}x)   final loss {loss:.4f}{extra}")
assert all(r[1] < 0.05 for r in res.values())
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
device: NVIDIA GeForce RTX 3050 Laptop GPU, compute capability (8, 6), bf16 supported: True
== A. formats
  torch.float32   1+8+23 bits  max  3.403e+38  smallest normal  1.175e-38  eps  1.19e-07
  torch.float16   1+5+10 bits  max   6.55e+04  smallest normal  6.104e-05  eps  0.000977
  torch.bfloat16  1+8+7  bits  max   3.39e+38  smallest normal  1.175e-38  eps   0.00781
  tf32 = fp32 range (8-bit exponent) with a 10-bit mantissa inside the tensor-core multiply; storage stays fp32
== B. 4096 x 4096 x 4096 matmul
  fp32 (no tf32)    45.99 ms    3.0 TFLOP/s   max rel. error vs fp64  2.6e-06
  tf32              22.52 ms    6.1 TFLOP/s   max rel. error vs fp64  2.7e-04
  fp16              11.41 ms   12.0 TFLOP/s   max rel. error vs fp64  4.4e-04
  bf16              10.91 ms   12.6 TFLOP/s   max rel. error vs fp64  3.5e-03
== C. failure modes
  fp16 overflow: [60000.0, 70000.0] -> [60000.0, inf];  300 * 300 in fp16 = inf
  bf16 rounding: 256 + 1 = 256.0; 1000 sequential bf16 additions of 1.0 = 256; torch.ones(1000, dtype=bfloat16).sum() = 1000 (the kernel accumulates in fp32)
  fp16 backward, loss scale       1: zero gradient entries 100.0%  mean |grad| 0.000e+00
  fp16 backward, loss scale   65536: zero gradient entries   0.0%  mean |grad| 8.700e-09
== D. 300 training steps, 6-layer MLP width 2048, batch 1024
  fp32                          63.02 ms/step (1.0x)   final loss 0.0017
  autocast fp16 + GradScaler    32.83 ms/step (1.9x)   final loss 0.0017   final GradScaler scale 65536
  autocast bf16 (no scaler)     34.68 ms/step (1.8x)   final loss 0.0017
ALL ASSERTIONS PASSED
```

* Tensor cores: fp16 and bf16 matmuls ran at ~12 TFLOP/s, **~4× fp32** (~3 TFLOP/s). TF32 ran at ~6 TFLOP/s with 2.7e-4 relative error instead of 2.6e-6. Since PyTorch 1.12 `allow_tf32` for matmuls defaults to off, so FP32 models don't get this unless you opt in (`torch.backends.cuda.matmul.allow_tf32 = True` or `torch.set_float32_matmul_precision("high")`).
* Error vs float64: fp16 4.4e-4, bf16 3.5e-3. bf16 trades ~8× precision for fp32's range.
* The failure modes are exactly the format table: fp16 overflows at 65504 (`300 * 300 = inf`). bf16 can't represent 257, so a bf16 running sum stalls at 256. **fp16 backward without scaling produced 100 % zero gradients; with the default 65536 scale, 0 %.**
* Training ran ~1.8–2.0× faster per step in both 16-bit formats (cool-GPU runs: fp32 ≈ 63 ms → fp16 ≈ 31–33 ms, bf16 ≈ 32–35 ms) with the same final loss (0.0017). The GradScaler held at 65536, never needing to back off. Under thermal throttling the same run measured 110 / 92 / 113 ms. ⚠ Benchmark only at a steady, known clock.

### 2.4 The caching allocator and fragmentation

```python
"""cuda_allocator_fragmentation.py - the CUDA caching allocator: allocated vs reserved, block rounding, fragmentation OOMs.

A: del does not return memory to the driver: allocated drops, reserved stays until empty_cache().
B: rounding and pools: tiny tensors take 512 B blocks carved from 2 MiB segments; mid-size from 20 MiB segments.
C: two patterns under a 1100 MiB cap, each in a fresh child process, default allocator vs
   PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True:
   holes   - 150 x 6 MiB tensors, free 2 of every 3 (live tensors pin the holes), then ask for 256 MiB;
   growing - a buffer that grows every step (64, 128, ... 640 MiB), freed in between (variable batch / sequence length).
"""
import os
import subprocess
import sys

import torch

MiB = 2**20


def stats():
    return torch.cuda.memory_allocated() / MiB, torch.cuda.memory_reserved() / MiB


def scenario(kind):
    dev = torch.device("cuda")
    torch.cuda.set_per_process_memory_fraction(1100 * MiB / torch.cuda.get_device_properties(0).total_memory)
    if kind == "holes":
        blocks = [torch.empty(6 * MiB, dtype=torch.uint8, device=dev) for _ in range(150)]
        for i in range(150):
            if i % 3:
                blocks[i] = None                         # every 18 MiB keeps one live 6 MiB block
        torch.cuda.empty_cache()
        alloc, res = stats()
        segs = len(torch.cuda.memory_snapshot())
        try:
            big = torch.empty(256 * MiB, dtype=torch.uint8, device=dev)
            outcome = "256 MiB OK"
            del big
        except torch.OutOfMemoryError as e:
            free = [s for s in str(e).split(". ") if "reserved by PyTorch but unallocated" in s]
            outcome = "256 MiB -> OutOfMemoryError (" + free[0].split(", and ")[-1].replace(" by PyTorch", "").rstrip(".") + ")"
        print(f"live {alloc:4.0f} MiB, reserved {res:4.0f} MiB after empty_cache() in {segs:2d} segment(s): {outcome}")
    else:
        for k in range(1, 11):
            buf = torch.empty(64 * k * MiB, dtype=torch.uint8, device=dev)
            del buf
        s = torch.cuda.memory_stats()
        print(f"peak live 640 MiB, reserved now {stats()[1]:4.0f} MiB; cudaMalloc calls {s['num_device_alloc']:2d}, "
              f"cudaFree calls {s['num_device_free']:2d}, alloc retries (free-all-and-retry) {s['num_alloc_retries']}")


if __name__ == "__main__" and len(sys.argv) > 2 and sys.argv[1] == "--child":
    scenario(sys.argv[2])
    sys.exit(0)

if __name__ == "__main__":
    dev = torch.device("cuda")
    torch.empty(1, device=dev)                           # create the CUDA context first
    print("== A. allocated vs reserved")
    print(f"  start                          allocated {stats()[0]:7.1f} MiB  reserved {stats()[1]:7.1f} MiB")
    t = torch.empty(256 * MiB, dtype=torch.uint8, device=dev)
    print(f"  t = empty(256 MiB)             allocated {stats()[0]:7.1f} MiB  reserved {stats()[1]:7.1f} MiB")
    del t
    print(f"  del t                          allocated {stats()[0]:7.1f} MiB  reserved {stats()[1]:7.1f} MiB  "
          f"(cached for reuse)")
    t2 = torch.empty(200 * MiB, dtype=torch.uint8, device=dev)
    print(f"  t2 = empty(200 MiB)            allocated {stats()[0]:7.1f} MiB  reserved {stats()[1]:7.1f} MiB  "
          f"(served from the cached block; no cudaMalloc)")
    del t2
    torch.cuda.empty_cache()
    print(f"  del t2; empty_cache()          allocated {stats()[0]:7.1f} MiB  reserved {stats()[1]:7.1f} MiB")
    assert stats()[1] < 64

    print("== B. rounding and pools")
    torch.cuda.empty_cache()
    base_a = torch.cuda.memory_allocated()
    tiny = [torch.empty(1, dtype=torch.uint8, device=dev) for _ in range(10)]
    print(f"  10 x 1-byte tensors            allocated {(torch.cuda.memory_allocated() - base_a):6d} B "
          f"(512 B blocks)  reserved {stats()[1]:5.1f} MiB (one 2 MiB small-pool segment)")
    mid = [torch.empty(6 * MiB, dtype=torch.uint8, device=dev) for _ in range(3)]
    segs = sorted({s["total_size"] // MiB for s in torch.cuda.memory_snapshot()})
    print(f"  + 3 x 6 MiB tensors            reserved {stats()[1]:5.1f} MiB; segment sizes (MiB): {segs}")
    del tiny, mid
    torch.cuda.empty_cache()

    print("== C. fragmentation under a 1100 MiB cap (fresh process each)")
    here = os.path.abspath(__file__)
    out = {}
    for kind in ("holes", "growing"):
        for label, conf in (("default allocator", None), ("expandable_segments:True", "expandable_segments:True")):
            env = dict(os.environ)
            env.pop("PYTORCH_CUDA_ALLOC_CONF", None)
            if conf:
                env["PYTORCH_CUDA_ALLOC_CONF"] = conf
            r = subprocess.run([sys.executable, here, "--child", kind], env=env, capture_output=True, text=True)
            assert r.returncode == 0, r.stderr[-500:]
            print(f"  {kind:8} {label:25} {r.stdout.strip()}")
            out[kind, conf] = r.stdout
    assert all("OutOfMemoryError" in out["holes", c] for c in (None, "expandable_segments:True"))
    retries = {c: int(out["growing", c].rsplit(" ", 1)[1]) for c in (None, "expandable_segments:True")}
    assert retries["expandable_segments:True"] < retries[None]
    print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. allocated vs reserved
  start                          allocated     0.0 MiB  reserved     2.0 MiB
  t = empty(256 MiB)             allocated   256.0 MiB  reserved   258.0 MiB
  del t                          allocated     0.0 MiB  reserved   258.0 MiB  (cached for reuse)
  t2 = empty(200 MiB)            allocated   200.0 MiB  reserved   258.0 MiB  (served from the cached block; no cudaMalloc)
  del t2; empty_cache()          allocated     0.0 MiB  reserved     0.0 MiB
== B. rounding and pools
  10 x 1-byte tensors            allocated   5120 B (512 B blocks)  reserved   2.0 MiB (one 2 MiB small-pool segment)
  + 3 x 6 MiB tensors            reserved  22.0 MiB; segment sizes (MiB): [2, 20]
== C. fragmentation under a 1100 MiB cap (fresh process each)
  holes    default allocator         live  300 MiB, reserved 1000 MiB after empty_cache() in 50 segment(s): 256 MiB -> OutOfMemoryError (700.00 MiB is reserved but unallocated)
  holes    expandable_segments:True  live  300 MiB, reserved  900 MiB after empty_cache() in  1 segment(s): 256 MiB -> OutOfMemoryError (600.00 MiB is reserved but unallocated)
  growing  default allocator         peak live 640 MiB, reserved now  640 MiB; cudaMalloc calls 10, cudaFree calls  9, alloc retries (free-all-and-retry) 3
  growing  expandable_segments:True  peak live 640 MiB, reserved now  640 MiB; cudaMalloc calls 10, cudaFree calls  1, alloc retries (free-all-and-retry) 1
ALL ASSERTIONS PASSED
```

* **A/B**: `del` returned nothing to the driver, and a later 200 MiB request reused the cached 256 MiB block without a `cudaMalloc`. One-byte tensors took 512 B blocks from a 2 MiB small-pool segment, and 6 MiB tensors came from a 20 MiB segment.
* **Holes**: with 300 MiB live, the default allocator held 1000 MiB in 50 segments (each pinned by one live 6 MiB block) and threw OOM for 256 MiB under a 1100 MiB cap, with "700 MiB reserved but unallocated". `empty_cache()` couldn't help, because no segment was entirely free.
* ⚠ **expandable_segments didn't rescue the holes case** on this Windows build. It used one 900 MiB segment (no 2 MiB tails) but kept the interior holes mapped even after `empty_cache()` and still threw OOM. It **did** fix the growing-buffer pattern (variable batch/sequence size): 1 `cudaFree` and 1 free-all-and-retry against 9 and 3 for the default allocator. Each retry synchronizes the device.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 ⚡ | `non_blocking=True` gives no overlap | Profiler: copies serialize with compute; CPU blocked in `cudaMemcpy` | Source tensor is pageable | `pin_memory=True` in the DataLoader, or `pin_memory()` once for reused buffers | Assert `batch.is_pinned()` in the input pipeline |
| F2 🔥 | Host results are zeros or stale | Reading after `copy_(..., non_blocking=True)` D2H | Copy still in flight | `event.synchronize()` / `stream.synchronize()` before reading | Wrap async D2H in a helper that returns an event |
| F3 | `RuntimeError: An attempt has been made to start a new process before the current process has finished its bootstrapping phase` | Windows/macOS, `num_workers > 0` | `spawn` re-imports the main module; no `__main__` guard | Put the training entry point under `if __name__ == "__main__":` | Template scripts with the guard |
| F4 🔥 | Host OOM with many workers | RSS grows linearly with `num_workers` | ~386 MiB runtime per spawned worker + a private dataset copy | Fewer workers, array-backed datasets, memory-mapped data | Budget RAM = workers × (runtime + dataset objects) |
| F5 🔥 | Linux: worker RSS grows through each epoch ("leak") | Python-object dataset with `fork` | Refcount writes dirty copy-on-write pages | NumPy/Arrow storage or memory-mapped files; avoid lists of objects | Review `Dataset.__init__` for per-row Python objects |
| F6 ⚡ | Each epoch starts with a multi-second stall | First batch slow every epoch | `persistent_workers=False` re-spawns workers | `persistent_workers=True` | Measure time-to-first-batch per epoch |
| F7 🔥 | Loss becomes NaN after enabling fp16 AMP | `scaler.get_scale()` collapsing toward 1 | Overflow in fp16 activations; ops forced to fp16 that need fp32 | Keep autocast's policy (don't `.half()` the model); bf16 where supported | Log the scale and skipped steps |
| F8 | bf16 training converges worse than fp32 | Drift in sums, optimizer states, metrics | bf16 accumulation (8-bit mantissa) | Accumulate in fp32; fp32 master weights and optimizer states | Ban `.bfloat16()` on optimizer state and loss reductions |
| F9 🔥 | OOM while "free" memory looks large | `X reserved by PyTorch but unallocated` in the error | Fragmentation: live blocks pin segments | Allocate long-lived tensors first; reuse buffers; `expandable_segments` for growth patterns | Memory snapshots in perf tests |
| F10 | `nvidia-smi` shows memory used after tensors are freed | Reserved ≫ allocated | Caching allocator design + CUDA context | Expected. `empty_cache()` only for sharing with other processes | Monitor `memory_allocated/reserved` from inside the process |
| F11 ⚡ | Benchmarks vary 30–70 % between runs | Clock and temperature drift | Thermal or power throttling (laptops, dense servers) | Warm up, fix clocks where allowed, report `nvidia-smi` clocks | Benchmark harness records clocks and temperature |
| F12 | Workers slow, CPU at 100 % | Many workers × many threads | Oversubscription: decode libraries spawn threads in each worker | Cap threads per worker (`OMP_NUM_THREADS`, `cv2.setNumThreads(0)`) | Thread budget = cores; see 05.1 |

**Debugging toolkit.** `torch.cuda.memory_summary()`, `memory_stats()` (`num_alloc_retries`, `num_device_alloc`, `num_device_free`, `inactive_split_bytes`); `torch.cuda.memory._record_memory_history()` → `_dump_snapshot("snap.pickle")`, viewed at `pytorch.org/memory_viz`; `torch.profiler` traces (stream lanes show copy/compute overlap); `torch.utils.data.get_worker_info()`; per-worker USS with `psutil.Process().children()` (`memory_full_info().uss`); `nvidia-smi --query-gpu=clocks.sm,temperature.gpu,power.draw,clocks_event_reasons.active --format=csv`.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why are `pin_memory=True` and `non_blocking=True` always used together?"</b></summary>

**Initial Prompt.** Explain the pair to a team that set only `non_blocking=True`.

**L5 Answer.** "Pinned memory is faster to copy, and non_blocking makes it async."

**Why L5 Crashes at Scale.** "Faster to copy" is the weaker half: pinned bandwidth was only 1.1–1.7× pageable here. The essential fact is that a copy from **pageable** memory can't be asynchronous. The driver must first memcpy it into a pinned staging buffer on the CPU, so the call blocks for the entire transfer whatever the flag says (measured ~32–42 ms vs ~0.07–0.09 ms). With only `non_blocking=True` the team gets no overlap and thinks the flag is broken.

**L7 Principal Defense.** The DMA engine needs physically locked pages. With `pin_memory=True` the DataLoader's pin thread places each batch in page-locked memory, and then `to(device, non_blocking=True)` enqueues a DMA and returns, so the CPU can prepare the next step while the copy runs. For explicit pipelines, put copies on their own stream with events: measured, a second stream hid ~72–107 % of the copy time. Don't over-pin. Page-locked memory is taken from the OS's pageable pool, and pinning gigabytes can starve the host, so pin batch-sized buffers, not datasets.

</details>

<details><summary><b>Q2 · "Our Linux DataLoader workers each grow to the full dataset size. Leak?"</b></summary>

**Initial Prompt.** A dataset of 50 M (path, label) tuples in a Python list. With 8 workers the host OOMs mid-epoch.

**L5 Answer.** "`fork` shares memory copy-on-write, so it shouldn't copy. It must be a leak in our code."

**Why L5 Crashes at Scale.** Copy-on-write only shares pages nobody writes. CPython increments `ob_refcnt` on every object it touches, so iterating a list writes to every object header and dirties every page holding them. Each worker ends up with a private copy: 8 workers × the dataset's object footprint. This is pytorch/pytorch#13246.

**L7 Principal Defense.** Remove per-row Python objects. Store paths as one Arrow string array or NumPy byte array with offsets, labels as a NumPy int array, or memory-map a file (Parquet/Arrow IPC/`np.memmap`) so the OS page cache shares it across workers at zero cost. A handful of buffer objects have a handful of refcounts. On `spawn` platforms the same design wins differently: the measured list of 500k tuples pickled to 7.5 MiB but cost ~58–62 MiB per worker once rebuilt as objects, against nothing extra for the NumPy version. Verify with per-worker USS, not RSS (RSS counts shared pages).

</details>

<details><summary><b>Q3 · "We set `num_workers=16` on our Mac/Windows workstations and training got slower."</b></summary>

**Initial Prompt.** Developers train locally; more workers made epochs slower.

**L5 Answer.** "Workers have overhead; use 4."

**Why L5 Crashes at Scale.** A magic number doesn't transfer to the cluster, and it doesn't explain the costs. Under `spawn`, each worker starts a fresh interpreter that imports torch (~2.5–3.9 s, ~386 MiB USS each here) and unpickles the dataset. Without `persistent_workers` this repeats **every epoch** (measured 4.2–5.6 s vs 0.7–1.0 s per epoch). And each worker's libraries may start their own thread pools.

**L7 Principal Defense.** Size workers from the decode budget: workers ≈ (target samples/s × CPU seconds per sample), capped by cores minus the main process's needs. Measured scaling was ~2.6–3.0× with 4 workers on 6 cores. Set `persistent_workers=True`, keep `prefetch_factor` at 2–4, cap per-worker threads, and keep datasets array-backed. Add RAM to the budget: workers × (runtime ≈ 0.4 GB + dataset objects). If decode is still the bottleneck, move preprocessing offline (pre-decoded shards, 08.1) or to the GPU.

</details>

<details><summary><b>Q4 · "fp16 or bf16 for training?"</b></summary>

**Initial Prompt.** Standardize the mixed-precision recipe across A100/H100 training and an older V100 fleet.

**L5 Answer.** "bf16 everywhere; it's the modern format."

**Why L5 Crashes at Scale.** V100 (sm_70) has no bf16 tensor cores. bf16 falls back to slow paths there, so "bf16 everywhere" quietly halves throughput on part of the fleet. And on bf16 hardware, ignoring its 8-bit mantissa breaks code that accumulates in bf16.

**L7 Principal Defense.** Both formats run at the same tensor-core rate where supported (measured ~11.7–12.7 TFLOP/s each, ~4× fp32 here; training ~1.8–2.0× faster at identical final loss). The difference is range vs precision. fp16 has 10 mantissa bits but tops out at 65504 and underflows below 6e-8, so it **needs a GradScaler** (measured: 100 % zero gradients unscaled vs 0 % at scale 65536). bf16 has fp32's range, so it needs no scaler, but only 8 bits of precision (`256 + 1 == 256`), so reductions and optimizer states must stay fp32. Recipe: bf16 autocast on Ampere and newer, fp16 + GradScaler on Volta; fp32 master weights, fp32 optimizer state and fp32 loss/softmax everywhere. Autocast's per-op lists already do the last part.

</details>

<details><summary><b>Q5 · "Training went NaN after enabling AMP."</b></summary>

**Initial Prompt.** fp16 AMP: loss becomes NaN at step ~3,000.

**L5 Answer.** "Lower the learning rate."

**Why L5 Crashes at Scale.** It treats a numerics bug as an optimization problem, slowing training permanently while the overflow is still possible. The cause is usually an fp16 overflow (activations above 65504, e.g. attention logits or unnormalized sums) or a model cast with `.half()` so autocast's fp32 safety list never applies.

**L7 Principal Defense.** Diagnose from the scaler: log `scaler.get_scale()` and skipped steps. A scale collapsing toward 1 means gradients overflow every step; a NaN *loss* means the forward overflowed, which the scaler can't fix. Check that the model isn't `.half()`ed (autocast should do the casting), that softmax, losses and norms run in fp32 (autocast's lists), and find the first non-finite tensor with forward hooks or `detect_anomaly`. Fixes, cheapest first: switch to bf16 on supporting hardware (fp32 range); keep the offending op in fp32 (`autocast(enabled=False)` locally); fix the model numerics (scaled attention, normalization).

</details>

<details><summary><b>Q6 · "CUDA OOM, but the error says 700 MiB is free."</b></summary>

**Initial Prompt.** Long-running training OOMs with `700 MiB is reserved by PyTorch but unallocated`.

**L5 Answer.** "Set `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`; the error message says so."

**Why L5 Crashes at Scale.** It might help, or might not. Measured here: with interleaved live and free blocks (300 MiB live spread over 50 segments), expandable segments still failed with 600 MiB reserved but unallocated, because live tensors pin the holes. Following the hint blindly costs a deploy and leaves the cause in place.

**L7 Principal Defense.** First identify the pattern from a memory snapshot (`_record_memory_history` → `memory_viz`). **Growth patterns** (a buffer that grows with batch or sequence length) fragment the classic allocator into many segments with free-all-and-retry storms; expandable segments fix that (measured 9 → 1 `cudaFree`, 3 → 1 retries). **Interleaved lifetimes** need allocation-order changes: allocate long-lived tensors (weights, optimizer state, static buffers) first, reuse preallocated buffers for variable data, pad shapes to buckets, and avoid keeping a small tensor from every step. `max_split_size_mb` stops large blocks from being split for small requests. Track `num_alloc_retries`: each retry synchronizes the device.

</details>

<details><summary><b>Q7 · "nvidia-smi says the GPU is full but our tensors are 1 GB."</b></summary>

**Initial Prompt.** Two services share one GPU; one can't start because the other "uses" 3.5 GB.

**L5 Answer.** "Call `torch.cuda.empty_cache()` after every request."

**Why L5 Crashes at Scale.** `empty_cache()` per request turns a pool into `cudaFree`/`cudaMalloc` churn (both synchronize) and still can't release segments that hold any live block. The real issue is that two processes share a device without a budget.

**L7 Principal Defense.** `nvidia-smi` shows reserved memory plus each CUDA context (hundreds of MiB). The caching allocator keeps freed blocks by design (measured: `del` left reserved at 258 MiB). For co-tenancy, give each process a budget with `torch.cuda.set_per_process_memory_fraction`, as the listing does with a 1100 MiB cap, and size it from measured peaks. Or isolate with MIG partitions or separate GPUs. Call `empty_cache()` only at phase boundaries (after loading, between jobs). Monitor `memory_allocated` and `memory_reserved` from inside each process.

</details>

<details><summary><b>Q8 · "How would you overlap data transfer and compute in a custom pipeline?"</b></summary>

**Initial Prompt.** A recommender streams 2 GB feature batches from host to GPU each step; transfers take 40 % of the step.

**L5 Answer.** "Use `non_blocking=True`."

**Why L5 Crashes at Scale.** On one stream, a non-blocking copy is still ordered before the next kernel on that stream: the GPU waits for the copy. Without pinned buffers it isn't even async on the host. And if a buffer allocated on one stream is used on another without `record_stream`, the allocator may hand it out again while the other stream still reads it, which corrupts data under load.

**L7 Principal Defense.** Double-buffer. Two pinned host buffers and two device buffers; a dedicated copy stream fills batch *n+1* while the compute stream works on batch *n*; an event per batch with `wait_event` on the compute side; `record_stream` (or allocation on the consuming stream) for allocator safety. Measured: the two-stream pipeline took about as long as compute alone. If copies exceed compute, overlap can't hide them. Then cut bytes (fp16/bf16 or int8 features, deduplicated embeddings looked up on the GPU) or move preprocessing onto the GPU.

</details>

<details><summary><b>Q9 · "Design the input pipeline for 2,000 images/s per GPU."</b></summary>

**Initial Prompt.** An 8-GPU node must sustain 16,000 JPEG decodes + augmentations per second.

**L5 Answer.** "Set `num_workers` to the number of cores."

**Why L5 Crashes at Scale.** At ~5 ms CPU per decoded and augmented image, 16,000/s needs ~80 cores, more than most 8-GPU nodes have. Worker count can't create CPU capacity, and Python-object datasets multiply RAM per worker.

**L7 Principal Defense.** Budget first: samples/s × CPU-seconds per sample = cores needed (the listing's ~0.5–0.9 ms decode stand-in is the kind of number to measure). Then pick tactics by gap. Pre-decode or pre-resize offline into sequential shards (WebDataset/Arrow/Parquet), which turns random file I/O into streaming reads. Decode on the GPU (nvJPEG via torchvision.io or DALI, ⚠ not run here). Keep datasets array-backed and memory-mapped, use persistent workers with bounded per-worker threads, pin memory, and copy on a side stream. Monitor data-loader wait time per step. If it isn't ~0, the GPUs are idling.

</details>

---

## 5. Invariants Checklist

- [ ] Asynchronous H2D needs pinned memory. Pageable sources block the CPU for the whole copy (32–42 ms vs ~0.1 ms here).
- [ ] Overlap needs separate streams plus events. One stream serializes copies and kernels.
- [ ] Never read a `non_blocking` D2H result before synchronizing.
- [ ] `spawn` workers re-import torch (~0.4 GB, ~3 s each). Use `persistent_workers=True` and a `__main__` guard.
- [ ] Python-object datasets cost per-worker RAM under both `fork` (CoW dirtied by refcounts) and `spawn` (unpickled copy). Store arrays or memory-map.
- [ ] fp16 needs loss scaling; bf16 needs fp32 accumulation. Both run at ~4× fp32 matmul throughput on tensor cores here.
- [ ] Reserved ≥ allocated. Fragmentation OOMs show "reserved but unallocated"; fix allocation order first and use `expandable_segments` for growth patterns.
- [ ] Laptop or thermally limited GPUs need clock-aware benchmarking.

---

## 6. References

- NVIDIA CUDA C++ Programming Guide: page-locked host memory, streams, asynchronous concurrent execution — https://docs.nvidia.com/cuda/cuda-c-programming-guide/
- M. Harris, "How to Optimize Data Transfers in CUDA C/C++", NVIDIA Developer Blog — https://developer.nvidia.com/blog/how-optimize-data-transfers-cuda-cc/
- PyTorch docs: CUDA semantics (streams, caching allocator, `PYTORCH_CUDA_ALLOC_CONF`) — https://docs.pytorch.org/docs/stable/notes/cuda.html
- PyTorch docs: understanding CUDA memory usage (snapshots) — https://docs.pytorch.org/docs/stable/torch_cuda_memory.html
- PyTorch docs: `torch.utils.data` (workers, pinning, `persistent_workers`) — https://docs.pytorch.org/docs/stable/data.html
- PyTorch docs: automatic mixed precision — https://docs.pytorch.org/docs/stable/amp.html
- PyTorch `c10/core/AllocatorConfig.h` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/c10/core/AllocatorConfig.h
- PyTorch `torch/amp/grad_scaler.py` (v2.14.1) — https://github.com/pytorch/pytorch/blob/v2.14.1/torch/amp/grad_scaler.py
- pytorch/pytorch#13246 — DataLoader workers and copy-on-write memory growth — https://github.com/pytorch/pytorch/issues/13246
- P. Micikevicius et al., "Mixed Precision Training", ICLR 2018 — https://arxiv.org/abs/1710.03740
- D. Kalamkar et al., "A Study of BFLOAT16 for Deep Learning Training", 2019 — https://arxiv.org/abs/1905.12322
