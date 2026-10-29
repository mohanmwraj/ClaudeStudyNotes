# 08.1 · Master Blueprint: An End-to-End Zero-Copy Pipeline from Parquet through Polars/Arrow to a PyTorch DataLoader

> **Folder 08 · Master Code Blueprints & FAANG L7 Interview Playbook**
> **Measured on:** pyarrow 26.0, Polars 2.1.0, pandas 3.1.0, NumPy 2.5.4, PyTorch 2.14.1+cu130 (RTX 3050 Laptop GPU), CPython 3.14.5 (`spawn` start method), i5-11260H (6C/12T), Windows 11.
> **Builds on:** Arrow buffers and the C Data Interface (02.3), Polars pushdown (03.2), Parquet internals (04.4), DataLoader physics and pinned memory (06.4).

---

## 0. Orientation & the JVM/C++ Bridge

This file assembles the whole KB into one pipeline. Feature data sits in Parquet. A lazy engine reads only the needed row groups and columns. Record batches become PyTorch tensors **without copying the bytes**, batches reach the GPU asynchronously, and an integrity check proves every row arrived exactly once. Each hop has a copy-or-no-copy decision, and the measured gap between the naive pipeline and this one is about **80–220×**.

```text
 object store / disk ─► Parquet (row groups, column chunks, zstd pages, min/max stats)
   │ predicate + projection pushdown: skip row groups, read 3 of N columns          (03.2, 04.4)
   ▼
 decode + decompress (Arrow C++, GIL released) ─► Arrow RecordBatch (validity, offsets, values buffers)
   │ filter = new buffers (materialization)                                         (02.3)
   ▼
 FixedSizeList<float32>[16] child buffer ─► np.frombuffer(...).reshape(n, 16) ─► torch.from_numpy  (0 copies)
   ▼
 pin_memory (one copy into page-locked memory) ─► .to(cuda, non_blocking=True) (DMA)  (06.4)
   ▼
 training step on the GPU; the loader prefetches the next batch meanwhile
```

| Hop | JVM analogue | C++ analogue |
|---|---|---|
| Parquet scan with pushdown | parquet-mr / Spark `FileSourceScanExec` with pushed filters | Arrow C++ `dataset::Scanner` |
| Arrow RecordBatch | Arrow Java `VectorSchemaRoot` over off-heap `ArrowBuf`s | `arrow::RecordBatch` |
| NumPy/torch view over Arrow memory | `MemorySegment` view over a direct buffer | `std::span` over a buffer |
| IterableDataset sharded by row group | Kafka consumer group partition assignment | static work partitioning |
| thread prefetcher | `CompletableFuture.supplyAsync` + bounded queue | a producer thread pool |
| pinned staging + DMA | `ByteBuffer.allocateDirect` + NIO zero-copy `transferTo` | `cudaHostAlloc` + `cudaMemcpyAsync` |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 Schema design decides whether zero copy is possible

```text
 "wide" schema: f0..f15 as 16 float32 columns
   Arrow: 16 separate value buffers (column-major); a (rows, 16) row-major matrix doesn't exist → np.column_stack
   copies: measured ~300–470 ms and 122 MiB new for 1M rows
 "tensor" schema: x as FixedSizeList<float32, 16> (Polars dtype Array(Float32, shape=(16,)))
   Arrow: ONE child values buffer laid out row-major: [x0_0 .. x0_15, x1_0 .. x1_15, ...]
   → np.frombuffer(child, float32).reshape(rows, 16) is a view; torch.from_numpy is a view (same address, asserted)
   Parquet stores it as a repeated leaf (4 leaf columns instead of 19), and the file was smaller here: 129 vs 181 MiB
 (Arrow also defines a canonical FixedShapeTensor extension type for N-d tensors over the same layout)
```

Rule: if a model consumes a fixed-width vector per row, store it as one fixed-size list column. Separate scalar columns are right for SQL analytics; for tensors they force a transpose copy on every read.

### 1.2 The copy ledger

```text
 hop                                        bytes copied?            measured / note
 Parquet pages → decompressed column        yes (decode is a write)   unavoidable; Arrow C++ releases the GIL
 filter (day >= 5)                          yes (selected rows)       materializes ~50 %; push filters down first
 Polars → Arrow (to_arrow)                  no                        C Data Interface export (02.3)
 Arrow child buffer → NumPy → torch         no                        same address (asserted in B)
 worker process → main process              yes (shared memory)       each tensor moved into shm by the worker
 pageable → pinned (pin_memory=True)        yes                       or allocate batches pinned up front
 pinned → GPU (non_blocking=True)           DMA                       async; overlaps the previous step (06.4)
```

### 1.3 Sharding a stream across workers, correctly

```text
 IterableDataset.__iter__ runs IN EACH WORKER; without sharding every worker yields the whole dataset (N x duplicates)
 shard by row group: groups[info.id :: info.num_workers]  → disjoint and complete by construction
 integrity check: total rows and sum(label) must equal the ground truth computed at write time (asserted for all variants)
 batch_size=None: the dataset yields whole batches; no per-sample __getitem__, no default_collate
 shuffling: a stream can't globally shuffle → shuffle row-group order per epoch (seeded) + a bounded in-memory
            shuffle buffer, or pre-shuffle when writing shards; check convergence, not only throughput
```

### 1.4 Workers or threads?

```text
 processes (num_workers > 0): parallel Python, but on spawn platforms each worker re-imports torch (~2.5–3.9 s,
   ~386 MiB USS; 06.4) and every batch crosses the process boundary through shared memory (a copy)
 threads: Parquet decode, zstd, Arrow compute (filter) run in C++ with the GIL released → threads give real
   parallelism for this pipeline with zero startup, no IPC copy, and zero-copy tensors
 measured for one pass over 2M rows (≈1M kept): in-process 1.25–1.33M rows/s; 2 spawned workers 0.23M rows/s
   (startup dominated the ~1 s job); 2-thread prefetcher 3.1–3.3M rows/s
 rule: processes when per-sample Python work dominates (augmentations in Python); threads when the work is in C++
   (Arrow, NumPy, PIL-SIMD, torchvision.io); free-threaded 3.14t extends threads to Python-level work (⚠ 01.2)
```

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

```python
"""zero_copy_pipeline.py - Parquet -> Polars/Arrow -> PyTorch -> GPU, end to end, with the copies counted.

A: one dataset, two layouts: 16 separate float32 columns ("wide") vs one FixedSizeList<float32>[16] column ("tensor").
B: Polars lazy scan (predicate + projection pushdown) -> Arrow -> NumPy -> torch: which hops are zero-copy (addresses).
C: the trap: pandas rows -> per-sample torch.tensor -> default collate.
D: the pattern: an IterableDataset streaming Arrow record batches, converted zero-copy per batch, sharded by row group
   across workers, batch_size=None (no per-sample collate), pinned, copied to the GPU with non_blocking=True;
   integrity check (row count, label sum) for every variant. Variants: in-process, 2 worker processes,
   and a 2-thread prefetcher (Parquet decode releases the GIL).
"""
import os
import queue
import threading
import time

import numpy as np
import pandas as pd
import polars as pl
import pyarrow as pa
import pyarrow.parquet as pq
import torch
from torch.utils.data import DataLoader, IterableDataset, get_worker_info

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")
N, F, RG, BATCH = 2_000_000, 16, 131_072, 16_384
dev = torch.device("cuda")


def write_data():
    os.makedirs(DATA, exist_ok=True)
    rng = np.random.default_rng(0)
    x = rng.standard_normal((N, F), dtype=np.float32)
    day = rng.integers(0, 10, N).astype(np.int16)
    label = (x[:, 0] + 0.5 * x[:, 1] > 0).astype(np.int8)
    wide = pa.table({"user_id": np.arange(N, dtype=np.int64), "day": day, "label": label,
                     **{f"f{i}": x[:, i] for i in range(F)}})
    flat = pa.array(x.reshape(-1))
    tensor = pa.table({"user_id": np.arange(N, dtype=np.int64), "day": day, "label": label,
                       "x": pa.FixedSizeListArray.from_arrays(flat, F)})
    for name, t in (("wide", wide), ("tensor", tensor)):
        pq.write_table(t, os.path.join(DATA, f"{name}.parquet"), row_group_size=RG, compression="zstd")
    return int(label[day >= 5].sum()), int((day >= 5).sum())


def consume(batches, limit_rows=None):
    """Move each batch to the GPU and run one small training step; return rows, label sum, rows/s."""
    model = torch.nn.Linear(F, 1).to(dev)
    opt = torch.optim.SGD(model.parameters(), lr=0.01)
    rows = lab = 0
    t0 = time.perf_counter()
    for x, y in batches:
        x = x.to(dev, non_blocking=True)
        y = y.to(dev, non_blocking=True)
        loss = torch.nn.functional.binary_cross_entropy_with_logits(model(x).squeeze(1), y.float())
        opt.zero_grad(set_to_none=True)
        loss.backward()
        opt.step()
        rows += len(y)
        lab += int(y.sum())                              # also a sync point per batch: keeps timing honest
        if limit_rows and rows >= limit_rows:
            break
    return rows, lab, rows / (time.perf_counter() - t0)


class RowDataset(torch.utils.data.Dataset):
    def __init__(self, frame):
        self.frame = frame

    def __len__(self):
        return len(self.frame)

    def __getitem__(self, i):
        row = self.frame.iloc[i]                         # a pandas Series per sample
        return torch.tensor([row[f"f{j}"] for j in range(F)], dtype=torch.float32), torch.tensor(row["label"])


class ArrowBatches(IterableDataset):
    """Stream record batches; each worker reads only its own row groups; zero-copy Arrow -> torch per batch."""

    def __init__(self, path, batch_rows=BATCH):
        self.path, self.batch_rows = path, batch_rows

    def __iter__(self):
        pf = pq.ParquetFile(self.path)
        info = get_worker_info()
        groups = list(range(pf.num_row_groups))
        if info is not None:
            groups = groups[info.id::info.num_workers]   # disjoint shards: no duplicates, nothing missed
        for rb in pf.iter_batches(batch_size=self.batch_rows, row_groups=groups, columns=["day", "x", "label"]):
            keep = pa.compute.greater_equal(rb.column("day"), 5)
            rb = rb.filter(keep)
            xs = rb.column("x")
            v = xs.values
            x = torch.from_numpy(np.frombuffer(v.buffers()[1], dtype=np.float32, count=len(xs) * F,
                                               offset=v.offset * 4).reshape(-1, F))
            y = torch.from_numpy(rb.column("label").to_numpy(zero_copy_only=True))
            yield x, y


def threaded(it_factory, n_threads=2, depth=8):
    """Prefetch batches with threads: Parquet decode and filtering run in Arrow's C++ with the GIL released."""
    q = queue.Queue(depth)
    shards = [ArrowShard(i, n_threads) for i in range(n_threads)]

    def work(shard):
        for item in it_factory(shard):
            q.put(item)
        q.put(None)

    for s in shards:
        threading.Thread(target=work, args=(s,), daemon=True).start()
    done = 0
    while done < n_threads:
        item = q.get()
        if item is None:
            done += 1
        else:
            yield item


class ArrowShard:
    def __init__(self, i, n):
        self.i, self.n = i, n


def shard_iter(path):
    def factory(shard):
        pf = pq.ParquetFile(path)
        groups = list(range(pf.num_row_groups))[shard.i::shard.n]
        for rb in pf.iter_batches(batch_size=BATCH, row_groups=groups, columns=["day", "x", "label"]):
            rb = rb.filter(pa.compute.greater_equal(rb.column("day"), 5))
            v = rb.column("x").values
            x = torch.from_numpy(np.frombuffer(v.buffers()[1], dtype=np.float32, count=rb.num_rows * F,
                                               offset=v.offset * 4).reshape(-1, F)).pin_memory()
            yield x, torch.from_numpy(rb.column("label").to_numpy(zero_copy_only=True))
    return factory


def sections_a_to_c():
    print(f"== A. {N:,} rows x {F} float32 features, row groups of {RG:,}, zstd")
    want_labels, want_rows = write_data()
    for name in ("wide", "tensor"):
        md = pq.ParquetFile(os.path.join(DATA, f"{name}.parquet")).metadata
        print(f"  {name:7} {os.path.getsize(os.path.join(DATA, name + '.parquet')) / 2**20:6.1f} MiB, "
              f"{md.num_row_groups} row groups, {md.num_columns} leaf columns")

    print("== B. Polars lazy scan (day >= 5, 2 of 4 columns) -> Arrow -> NumPy -> torch")
    t0 = time.perf_counter()
    df = (pl.scan_parquet(os.path.join(DATA, "tensor.parquet")).filter(pl.col("day") >= 5).select("x", "label")
          .collect())
    t_scan = time.perf_counter() - t0
    tbl = df.to_arrow()
    xcol = tbl.column("x").combine_chunks()
    values = xcol.values                                     # the FixedSizeList child: one contiguous float32 buffer
    arrow_addr = values.buffers()[1].address + values.offset * 4
    xn = np.frombuffer(values.buffers()[1], dtype=np.float32, count=len(xcol) * F,
                       offset=values.offset * 4).reshape(-1, F)
    xt = torch.from_numpy(xn)
    print(f"  scan + filter + collect: {df.height:,} rows in {t_scan * 1e3:.0f} ms (Polars dtype {df.schema['x']})")
    print(f"  Arrow child buffer -> NumPy (rows, {F}) -> torch: same address: "
          f"{arrow_addr == xn.ctypes.data == xt.data_ptr()}; NumPy writeable: {xn.flags.writeable}")
    assert arrow_addr == xn.ctypes.data == xt.data_ptr() and df.height == want_rows
    wide = pl.read_parquet(os.path.join(DATA, "wide.parquet"), columns=[f"f{i}" for i in range(F)]).to_arrow()
    t0 = time.perf_counter()
    xw = np.column_stack([wide.column(f"f{i}").to_numpy() for i in range(F)])
    t_stack = time.perf_counter() - t0
    print(f"  wide layout: 16 column buffers -> one (rows, 16) matrix needs a copy: {t_stack * 1e3:.0f} ms, "
          f"{xw.nbytes / 2**20:.0f} MiB new (C-contiguous: {xw.flags.c_contiguous})")
    del df, tbl, xcol, values, xn, xt, wide, xw
    print("== C. the trap: pandas -> per-row Python -> torch.tensor per sample -> default collate (first 100k rows)")
    pdf = pd.read_parquet(os.path.join(DATA, "wide.parquet")).head(100_000)
    rows, _, rate_trap = consume(DataLoader(RowDataset(pdf), batch_size=1024))
    print(f"  {rows:,} rows at {rate_trap:,.0f} rows/s")
    del pdf
    return want_labels, want_rows, rate_trap


if __name__ == "__main__":                               # spawn re-imports this module in every worker
    want_labels, want_rows, rate_trap = sections_a_to_c()
    print("== D. the pattern: streaming Arrow batches (all 2M rows scanned, day >= 5 kept), GPU training step per batch")
    path = os.path.join(DATA, "tensor.parquet")
    res = {}
    for label, loader in (
            ("IterableDataset, in-process", DataLoader(ArrowBatches(path), batch_size=None, pin_memory=True)),
            ("IterableDataset, 2 worker processes", DataLoader(ArrowBatches(path), batch_size=None, pin_memory=True,
                                                               num_workers=2)),
            ("2-thread prefetcher, no processes", threaded(shard_iter(path)))):
        rows, lab, rate = consume(loader)
        res[label] = rate
        ok = rows == want_rows and lab == want_labels
        print(f"  {label:38} {rows:,} rows, label sum ok: {ok}, {rate:12,.0f} rows/s ({rate / rate_trap:5.0f}x the trap)")
        assert ok
    print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. 2,000,000 rows x 16 float32 features, row groups of 131,072, zstd
  wide     181.0 MiB, 16 row groups, 19 leaf columns
  tensor   129.0 MiB, 16 row groups, 4 leaf columns
== B. Polars lazy scan (day >= 5, 2 of 4 columns) -> Arrow -> NumPy -> torch
  scan + filter + collect: 999,675 rows in 145 ms (Polars dtype Array(Float32, shape=(16,)))
  Arrow child buffer -> NumPy (rows, 16) -> torch: same address: True; NumPy writeable: True
  wide layout: 16 column buffers -> one (rows, 16) matrix needs a copy: 302 ms, 122 MiB new (C-contiguous: True)
== C. the trap: pandas -> per-row Python -> torch.tensor per sample -> default collate (first 100k rows)
  100,000 rows at 14,942 rows/s
== D. the pattern: streaming Arrow batches (all 2M rows scanned, day >= 5 kept), GPU training step per batch
  IterableDataset, in-process            999,675 rows, label sum ok: True,    1,325,214 rows/s (   89x the trap)
  IterableDataset, 2 worker processes    999,675 rows, label sum ok: True,      230,179 rows/s (   15x the trap)
  2-thread prefetcher, no processes      999,675 rows, label sum ok: True,    3,252,314 rows/s (  218x the trap)
ALL ASSERTIONS PASSED
```

* **B**: Polars scanned, filtered and projected 2M rows in ~130–520 ms (the first, cold read is the slow end), and its `Array(Float32, 16)` column reached torch with **the same address at every hop**. The wide schema paid a 122 MiB copy just to build the matrix.
* **C, the trap**: pandas row → Python list → `torch.tensor` per sample → default collate ran at **~13–15k rows/s**. Every sample allocates several Python objects and small tensors (06.1's per-op tax, times 16 features).
* **D, the pattern**: streaming record batches with zero-copy conversion reached **~1.25–1.33M rows/s in-process (~80–90×)** and **~3.1–3.3M rows/s with two prefetch threads (~200–220×)**, and passed the row-count and label-sum integrity check. Two spawned workers managed only ~0.23M rows/s, because spawn startup and shared-memory copies dominate a one-second job.
* The first draft of this listing kept its data-generation code at module level. Under `spawn` each worker re-imported the module and re-ran it, rewriting the Parquet files mid-read and printing sections A–C three times. That's 06.4's F3, reproduced by accident. All work now sits under `if __name__ == "__main__":`.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Model sees each sample N times per epoch | Rows/epoch = N × dataset | IterableDataset not sharded per worker | Shard by `get_worker_info()` (row groups/files) | Integrity check: row count + label checksum per epoch |
| F2 | `UserWarning: The given NumPy array is not writable` | `torch.from_numpy` on Arrow buffers | Arrow memory is immutable | Treat as read-only (no in-place ops), or copy deliberately | Document read-only tensors at the loader boundary |
| F3 | `ArrowInvalid: Needed to copy ... zero_copy_only=True` | Column with nulls or chunked | Validity bitmap or multiple chunks | Fill nulls upstream; `combine_chunks` once (a copy) | Non-null schema for features; size row groups |
| F4 🔥 | Each epoch slower than the last / RAM growth | Workers re-run module code | `spawn` re-imports the main module | Everything under `__main__`; side-effect-free imports | Lint for module-level work in training scripts |
| F5 ⚡ | GPU idle, loader at 100 % CPU | Per-sample Python, default collate | Map-style dataset over pandas rows | Batch-level IterableDataset, `batch_size=None` | Loader-only benchmark (rows/s) before training |
| F6 | Strings in features break zero copy | object/str columns | Variable-length data can't be a tensor view | Encode to integer ids/embeddings upstream | Schema review: tensors are fixed-width |
| F7 | Workers finish unevenly; long epoch tail | One worker gets the big row groups | Skewed row-group sizes | Uniform row groups (`row_group_size`), more shards than workers | Check row-group sizes in the writer |
| F8 | Convergence worse than with a map-style loader | Correlated batches | No shuffle in streaming | Shuffle row-group order per epoch + shuffle buffer; pre-shuffled shards | Track validation curves when changing loaders |
| F9 | Resume after failure repeats or skips data | Restart from epoch start | No mid-epoch cursor | Checkpoint (epoch, row-group cursor, RNG) per worker (`torchdata` StatefulDataLoader ⚠) | Resume test in CI |

**Debugging toolkit.** `pq.ParquetFile(path).metadata` (row groups, sizes, statistics); Polars `explain()` for pushdown; `buffer.address` vs `ndarray.ctypes.data` vs `tensor.data_ptr()` for zero-copy proofs; a loader-only loop (no model) measuring rows/s; `torch.utils.data.get_worker_info()` logging per worker; integrity checksums per epoch; `py-spy dump` on a slow worker (⚠ not run).

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Design the input pipeline from Parquet on S3 to 8 GPUs."</b></summary>

**Initial Prompt.** 2 TB of feature Parquet on object storage; 8-GPU training node; the GPUs must never wait.

**L5 Answer.** "Load with pandas into a Dataset and use DataLoader with 16 workers."

**Why L5 Crashes at Scale.** 2 TB doesn't fit in RAM. Per-sample pandas access ran at ~13–15k rows/s here (one core), and under `spawn` each worker holds its own copy of whatever the dataset object references. Sixteen workers multiply RAM and still pay Python per sample.

**L7 Principal Defense.** Stream instead. Shard files or row groups across nodes, GPUs and workers (disjoint by construction). Read with pushdown (row-group statistics and projection). Decode record batches in Arrow C++ (GIL released). Convert batches zero-copy to tensors from a FixedSizeList feature column (same address across Arrow → NumPy → torch, asserted). Yield whole batches (`batch_size=None`), pin, and copy with `non_blocking`. Use threads for C++-bound decode (3.1–3.3M rows/s measured vs 1.25–1.33M in-process) and processes only for Python-heavy augmentation. Verify with a loader-only benchmark and per-epoch integrity checksums, and size object-store parallelism (concurrent range GETs) to the target rows/s.

</details>

<details><summary><b>Q2 · "Where exactly are the copies in your pipeline?"</b></summary>

**Initial Prompt.** The team claims "zero copy end to end." Audit it.

**L5 Answer.** "Arrow is zero-copy, so there are none."

**Why L5 Crashes at Scale.** Decompression writes new bytes, filters materialize, process boundaries copy into shared memory, pinning copies into page-locked memory, and H2D is a DMA transfer. Claiming zero copies hides where memory bandwidth and RAM actually go.

**L7 Principal Defense.** Keep a copy ledger (§1.2). Unavoidable: decode/decompress, the H2D DMA. Avoidable by design: a transpose from wide columns (122 MiB, ~300–470 ms per 1M rows measured), filter materialization (push predicates into the scan), shared-memory transfer (threads instead of processes), the pinning copy (allocate pinned batch buffers once and decode into them, or use the DataLoader pin thread off the critical path). "Zero copy" correctly means **no copies between Arrow, NumPy and torch inside one process**, which the listing proves with addresses.

</details>

<details><summary><b>Q3 · "num_workers or threads for the loader?"</b></summary>

**Initial Prompt.** On Windows and macOS dev machines training is slow to start and RAM-hungry with `num_workers=8`.

**L5 Answer.** "Always use worker processes because of the GIL."

**Why L5 Crashes at Scale.** "Because of the GIL" is only true when the work is Python bytecode. Parquet decoding, decompression and Arrow compute release the GIL, so threads run them in parallel. Processes add spawn startup (~2.5–3.9 s and ~386 MiB each, 06.4) and an IPC copy per batch.

**L7 Principal Defense.** Profile where loader time goes. If it's in C++ (Arrow, NumPy, image libraries that release the GIL), use a thread prefetcher (measured 3.1–3.3M rows/s against 0.23M with 2 spawned workers for the same pass). If it's in Python per-sample transforms, use processes with `persistent_workers=True`, array-backed state, and a `__main__` guard. On Linux `fork` startup is cheaper, but copy-on-write refcount traffic (06.4) still applies. Free-threaded 3.14t will make threads viable for Python-level transforms once dependencies support it (⚠ not runnable here).

</details>

<details><summary><b>Q4 · "Prove your streaming loader neither duplicates nor drops data."</b></summary>

**Initial Prompt.** An auditor asks how you know each example is seen exactly once per epoch.

**L5 Answer.** "The DataLoader handles that."

**Why L5 Crashes at Scale.** For `IterableDataset` it doesn't. Each worker runs `__iter__` independently, so without explicit sharding every worker emits the full stream (N× duplication). Restarts can also repeat or skip shards.

**L7 Principal Defense.** Shard deterministically (row groups or files by `worker_id`, and by rank under DDP), so partitions are disjoint and complete by construction. Then verify it at run time: compute (row count, label sum or a hash of IDs) at write time and compare per epoch. The listing asserts both for in-process, process and thread variants. For resumability, checkpoint the per-worker cursor (row-group index, offset, RNG state) with the model checkpoint, and test kill-and-resume in CI.

</details>

<details><summary><b>Q5 · "How should features be laid out in Parquet for training?"</b></summary>

**Initial Prompt.** A Spark job writes 300 float features as 300 columns.

**L5 Answer.** "Columns are the standard; the loader can stack them."

**Why L5 Crashes at Scale.** Stacking is a transpose copy per batch: 16 columns cost ~300–470 ms and 122 MiB per 1M rows here, and it scales with feature count. It also produces 300 leaf columns of Parquet metadata per row group.

**L7 Principal Defense.** Store fixed-width model inputs as one `FixedSizeList<float32>[d]` column (or the Arrow FixedShapeTensor extension type). Its child buffer is already a row-major (rows, d) matrix, so readers get a zero-copy view (asserted). Keep scalar columns for anything you filter, join or aggregate on (`day`, IDs, labels), and keep them non-null. Size row groups for parallelism (~128k rows here, uniform), sort or cluster by the common filter column so min/max pruning works (03.3, 04.4), and use zstd. From Spark, write `array<float>` columns, which map to list types, and cast to fixed-size on read where needed.

</details>

<details><summary><b>Q6 · "The GPUs sit at 40 % utilization. Is it the input pipeline?"</b></summary>

**Initial Prompt.** Training throughput is half the expected rate.

**L5 Answer.** "Add more workers."

**Why L5 Crashes at Scale.** It's a guess. The bottleneck might be the loader, the H2D copy (pageable memory, no overlap), sync points in the step (06.1), or the model itself.

**L7 Principal Defense.** Measure each stage in isolation. Run a loader-only loop (rows/s with no model; the listing's numbers are this kind), a model-only loop on synthetic GPU tensors (steps/s), and the combined loop with per-step "time waiting for data". If loader rows/s < model rows/s, fix the loader: batch-level zero-copy, threads vs processes, pushdown, storage parallelism. If copies stall, check `is_pinned()` and `non_blocking`. If neither, it's the step itself (launch-bound, sync points). Report the stage throughputs side by side; the minimum is the system's throughput.

</details>

<details><summary><b>Q7 · "Our JVM pipeline produces the training data. What's the contract?"</b></summary>

**Initial Prompt.** A Flink/Spark team owns feature generation; the ML team owns training in Python.

**L5 Answer.** "They write CSV or JSON and we parse it."

**Why L5 Crashes at Scale.** Text formats cost parsing CPU on every epoch (Python-side parsing is the per-row trap), lose types (float precision, nulls), and can't be pruned or projected.

**L7 Principal Defense.** The contract is a **typed Arrow schema** written as Parquet: fixed-size list feature columns, non-null scalars for filters and labels, explicit dtypes, partitioning and sort order by the training-time filter (date), uniform row-group size, zstd. Version it like an API, with schema evolution rules and validation in the producer. Both sides then speak Arrow: Spark/Flink via Arrow Java, Python via pyarrow/Polars, zero-copy into torch. For online features, use Arrow Flight or Arrow IPC streams instead of JSON. Add a contract test: the producer writes a sample, the consumer's loader reads it zero-copy and passes the integrity check.

</details>

<details><summary><b>Q8 · "When should preprocessing move to the GPU?"</b></summary>

**Initial Prompt.** Even with threads, the CPU can't feed 8 GPUs with image augmentation.

**L5 Answer.** "Buy a bigger CPU."

**Why L5 Crashes at Scale.** Decode budgets grow with GPU speed. At ~5 ms CPU per image, 16,000 images/s needs ~80 cores (napkin math, 08.3), more than the node has.

**L7 Principal Defense.** First remove repeated work: pre-decode or pre-resize offline into tensor shards (this file's pattern), cache deterministic transforms, and keep only random augmentations online. Then move decode and augmentation onto the GPU (nvJPEG via `torchvision.io.decode_jpeg(device="cuda")`, DALI, cuDF for tabular transforms; ⚠ not run here), where it costs a few percent of GPU time instead of whole cores. Keep the CPU path for I/O and batching. Measure end to end; GPU preprocessing competes with training for memory and SMs.

</details>

---

## 5. Invariants Checklist

- [ ] Store model inputs as fixed-size list (tensor) columns. Wide scalar columns force a transpose copy per read.
- [ ] Arrow → NumPy → torch is zero-copy inside a process. Prove it with addresses.
- [ ] Push filters and projections into the scan; filters after decode materialize new buffers.
- [ ] `IterableDataset` must shard per worker (and per rank). Verify with per-epoch integrity checksums.
- [ ] Yield batches (`batch_size=None`), not samples. Default collate over per-sample tensors is the slow trap (~13–15k rows/s).
- [ ] Use threads when the work is in C++ (GIL released), processes when it's in Python. Spawn costs seconds and an IPC copy per batch.
- [ ] Put all work under `if __name__ == "__main__":`. Spawn re-imports the module in every worker.
- [ ] Measure loader, copy and model throughput separately; the minimum is the system.

---

## 6. References

- Apache Arrow columnar format (FixedSizeList, buffers) — https://arrow.apache.org/docs/format/Columnar.html
- Apache Arrow canonical extension types (FixedShapeTensor) — https://arrow.apache.org/docs/format/CanonicalExtensions.html
- PyArrow `ParquetFile.iter_batches` — https://arrow.apache.org/docs/python/generated/pyarrow.parquet.ParquetFile.html
- Polars `scan_parquet` and the Array dtype — https://docs.pola.rs/api/python/stable/reference/api/polars.scan_parquet.html
- PyTorch docs: `IterableDataset` and worker sharding — https://docs.pytorch.org/docs/stable/data.html#dataset-types
- PyTorch docs: `torch.from_numpy` — https://docs.pytorch.org/docs/stable/generated/torch.from_numpy.html
- Apache Parquet format (row groups, statistics) — https://parquet.apache.org/docs/file-format/
- NVIDIA DALI — https://docs.nvidia.com/deeplearning/dali/user-guide/docs/
