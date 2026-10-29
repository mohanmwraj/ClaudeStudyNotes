# 08.3 · 35 FAANG L7 Bar-Raiser Q&As: Python Data Engineering & ML Systems

> **Folder 08 · Master Code Blueprints & FAANG L7 Interview Playbook**
> **How to use this file:** each chain is cross-cutting (system design, debugging or estimation) and cites the folder where its numbers were measured. The per-file chains in Folders 01–07 drill into single mechanisms; these test whether you can combine them under pressure. The napkin-math listing below computes every estimate used here.

---

## 0. Orientation & the JVM/C++ Bridge

At L7 the bar isn't knowing more facts. It's turning a vague symptom into a mechanism, a number and a decision with a validation plan. The table shows the signals interviewers separate on.

| Dimension | L5 signal | L7 signal |
|---|---|---|
| Framing | names a tool ("use Polars") | names the bottleneck and the resource it consumes (bytes, cores, launches, GIL, links) |
| Mechanism | "Python is slow" | "per-row boxing: ~197 B/row and a Python call per element" |
| Numbers | none, or memorized benchmarks | napkin math from first principles plus a measurement plan |
| Trade-offs | one solution | 2–3 options with the cost each one pays |
| Failure modes | the happy path | what breaks at 10× load, on restart, under skew, on another platform |
| Validation | "it should work" | the test, metric or experiment that would prove it |
| JVM/C++ bridge | "Python is like Java but…" | the precise analogue and where it stops holding |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 The answer skeleton

```text
 1. Restate the workload as rates and sizes        (rows/s, bytes/row, QPS, tokens, parameters)
 2. Locate the bottleneck resource                 (CPU-Python | CPU-native | memory capacity | DRAM/HBM bandwidth |
                                                    PCIe | network | launch overhead | locks/GIL | storage IOPS)
 3. Explain the mechanism at the level below       (C structs, buffers, kernels, collectives, queues)
 4. Quantify: napkin math, then what you'd measure (the listing below; the KB's measured numbers)
 5. Options with costs; pick one and say why
 6. Failure modes and operations                   (skew, restarts, cold start, platform differences)
 7. Validation                                     (benchmark, integrity check, A/B, parity test, SLO)
```

### 1.2 Question index

| # | Domain | Question (short) | Folders |
|---|---|---|---|
| 1–5 | CPython & concurrency | memory blow-up, GC spikes, CPU threads, event-loop starvation, IPC for big arrays | 01 |
| 6–9 | NumPy & Arrow | temporaries, C Data Interface design, strings, SIMD | 02, 03 |
| 10–13 | Engines | engine choice, pruning, as-of joins, memory profiling | 03 |
| 14–17 | Distributed data | PySpark vs Scala, Beam inference, Ray object store, lakehouse tables | 04 |
| 18–20 | Classical ML | offline/online gap, calibration, GBDT latency | 05 |
| 21–25 | PyTorch internals | backward end to end, hidden copies, when not to compile, numerics policy, late OOM | 06 |
| 26–29 | Distributed training | pretraining estimate, 13B strategy, sharded checkpoints, fault tolerance | 07.1 |
| 30–32 | PEFT, quantization, attention | 50 variants, long-context memory, decode speed | 07.2 |
| 33–35 | Serving & architecture | 100k-QPS design, safe model rollout, end-to-end platform | 07.3, 08 |

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

The trap in interviews is quoting numbers you can't derive. The pattern is computing them in front of the interviewer from a few constants you can defend. This listing does every computation the chains below use:

```python
"""l7_napkin_math.py - the back-of-envelope numbers behind the 35 bar-raiser answers, computed instead of recalled.

Inputs are either measured in this KB (folder noted) or stated assumptions (marked "assumed"). Output is deterministic.
A: bytes per row: Python objects (tracemalloc, measured here) vs Arrow/NumPy columns, scaled to 100M rows.
B: CPU budgets: cores needed = events/s x cost per event, for per-row Python, pickled UDFs, Arrow UDFs, image decode.
C: LLM and training arithmetic: weight bytes by format, KV cache per token, decode ceilings, 6ND training FLOPs,
   all-reduce time, ZeRO-3 memory.
D: queueing: M/D/1 waiting time vs utilization; Little's law for pool sizing.
"""
import tracemalloc

print("== A. 100M rows of (int64 id, float64 value, 20-char string)")
tracemalloc.start()
before = tracemalloc.get_traced_memory()[0]
rows = [(i, i * 0.5, f"user-{i:015d}") for i in range(100_000)]
per_row = (tracemalloc.get_traced_memory()[0] - before) / len(rows)
tracemalloc.stop()
arrow_row = 8 + 8 + 20 + 4                               # id + value + string bytes + int32 offset
view_row = 8 + 8 + 16 + 20                               # Utf8View: 16-byte view + out-of-line bytes (> 12 chars)
for label, b in (("list of Python tuples (measured)", per_row), ("Arrow / NumPy columns (utf8)", arrow_row),
                 ("Arrow with Utf8View strings", view_row)):
    print(f"  {label:34} {b:6.1f} B/row -> {b * 1e8 / 2**30:6.1f} GiB")
assert per_row > 3 * arrow_row

print("== B. cores = events/s x CPU-seconds per event")
rate = 1_000_000
for label, ns in (("pure-Python dict handling, ~5 us/event (assumed)", 5000),
                  ("Spark pickled Python UDF, ~380 ns/row (Folder 04)", 380),
                  ("Spark Arrow UDF, ~110 ns/row (Folder 04)", 110),
                  ("JVM-native expression, ~5 ns/row (Folder 04)", 5)):
    print(f"  {label:52} {rate * ns / 1e9:7.2f} cores at {rate:,} events/s")
img_rate, decode_ms = 16_000, 5.0
print(f"  JPEG decode + augment {decode_ms} ms each (assumed) at {img_rate:,} img/s: {img_rate * decode_ms / 1e3:.0f} cores")

print("== C. LLM and training arithmetic")
for params in (7e9, 70e9):
    row = ", ".join(f"{fmt} {params * bits / 8 / 1e9:6.1f} GB" for fmt, bits in
                    (("fp16", 16), ("int8", 8), ("int4 g128", 4.125), ("NF4+DQ", 4.127)))
    print(f"  {params / 1e9:.0f}B weights: {row}")
for label, layers, kv_heads, hd in (("7B MHA (32 layers, 32 KV heads)", 32, 32, 128), ("70B GQA (80 layers, 8 KV heads)", 80, 8, 128)):
    per_tok = 2 * layers * kv_heads * hd * 2
    print(f"  KV cache {label}: {per_tok / 2**10:.0f} KiB/token -> {per_tok * 4096 / 2**30:.2f} GiB per 4k-token sequence")
for gpu, bw in (("H100 SXM, 3.35 TB/s (assumed datasheet)", 3.35e12), ("RTX 3050 Laptop, ~160 GB/s (measured, Folder 06; 14 GB fp16 would not fit in 4 GB)", 160e9)):
    w16, w4 = 7e9 * 2, 7e9 * 4.125 / 8
    print(f"  batch-1 decode ceiling, 7B on {gpu}: fp16 {bw / w16:5.0f} tok/s, int4 {bw / w4:5.0f} tok/s")
n_params, tokens, peak, mfu = 7e9, 2e12, 989e12, 0.40
flops = 6 * n_params * tokens
gpu_hours = flops / (peak * mfu) / 3600
print(f"  training 7B on 2T tokens: 6ND = {flops:.2e} FLOPs; at 40% MFU of 989 TFLOP/s (assumed) = {gpu_hours:,.0f} "
      f"GPU-hours = {gpu_hours / 1024 / 24:.1f} days on 1,024 GPUs")
grad_bytes, n, busbw = 1e9 * 2, 8, 450e9
t_ar = 2 * (n - 1) / n * grad_bytes / busbw
print(f"  DDP all-reduce of 1B bf16 grads on 8 GPUs at 450 GB/s busbw (assumed NVLink): {t_ar * 1e3:.1f} ms per step")
psi, ranks = 13e9, 32
print(f"  13B on {ranks} GPUs, mixed-precision AdamW: DDP {16 * psi / 1e9:.0f} GB/GPU, ZeRO-3 {16 * psi / ranks / 1e9:.1f} GB/GPU "
      f"(+ activations)")
assert abs(gpu_hours - 58_982) < 50

print("== D. queueing and pools")
mu = 1000.0                                              # 1 ms deterministic service time
for rho in (0.5, 0.8, 0.9, 0.95, 0.99):
    wq = rho / (2 * mu * (1 - rho))
    print(f"  M/D/1, service 1 ms, utilization {rho:4.2f}: mean queueing delay {wq * 1e3:6.2f} ms")
for thr, lat in ((2000, 0.05), (20000, 0.2)):
    print(f"  Little's law: {thr:,} req/s x {lat * 1e3:.0f} ms = {thr * lat:,.0f} requests in flight "
          f"(size connection pools and queues for this)")
print("ALL ASSERTIONS PASSED")
```

Output (deterministic, verified):

```text
== A. 100M rows of (int64 id, float64 value, 20-char string)
  list of Python tuples (measured)    196.9 B/row ->   18.3 GiB
  Arrow / NumPy columns (utf8)         40.0 B/row ->    3.7 GiB
  Arrow with Utf8View strings          52.0 B/row ->    4.8 GiB
== B. cores = events/s x CPU-seconds per event
  pure-Python dict handling, ~5 us/event (assumed)        5.00 cores at 1,000,000 events/s
  Spark pickled Python UDF, ~380 ns/row (Folder 04)       0.38 cores at 1,000,000 events/s
  Spark Arrow UDF, ~110 ns/row (Folder 04)                0.11 cores at 1,000,000 events/s
  JVM-native expression, ~5 ns/row (Folder 04)            0.01 cores at 1,000,000 events/s
  JPEG decode + augment 5.0 ms each (assumed) at 16,000 img/s: 80 cores
== C. LLM and training arithmetic
  7B weights: fp16   14.0 GB, int8    7.0 GB, int4 g128    3.6 GB, NF4+DQ    3.6 GB
  70B weights: fp16  140.0 GB, int8   70.0 GB, int4 g128   36.1 GB, NF4+DQ   36.1 GB
  KV cache 7B MHA (32 layers, 32 KV heads): 512 KiB/token -> 2.00 GiB per 4k-token sequence
  KV cache 70B GQA (80 layers, 8 KV heads): 320 KiB/token -> 1.25 GiB per 4k-token sequence
  batch-1 decode ceiling, 7B on H100 SXM, 3.35 TB/s (assumed datasheet): fp16   239 tok/s, int4   928 tok/s
  batch-1 decode ceiling, 7B on RTX 3050 Laptop, ~160 GB/s (measured, Folder 06; 14 GB fp16 would not fit in 4 GB): fp16    11 tok/s, int4    44 tok/s
  training 7B on 2T tokens: 6ND = 8.40e+22 FLOPs; at 40% MFU of 989 TFLOP/s (assumed) = 58,982 GPU-hours = 2.4 days on 1,024 GPUs
  DDP all-reduce of 1B bf16 grads on 8 GPUs at 450 GB/s busbw (assumed NVLink): 7.8 ms per step
  13B on 32 GPUs, mixed-precision AdamW: DDP 208 GB/GPU, ZeRO-3 6.5 GB/GPU (+ activations)
== D. queueing and pools
  M/D/1, service 1 ms, utilization 0.50: mean queueing delay   0.50 ms
  M/D/1, service 1 ms, utilization 0.80: mean queueing delay   2.00 ms
  M/D/1, service 1 ms, utilization 0.90: mean queueing delay   4.50 ms
  M/D/1, service 1 ms, utilization 0.95: mean queueing delay   9.50 ms
  M/D/1, service 1 ms, utilization 0.99: mean queueing delay  49.50 ms
  Little's law: 2,000 req/s x 50 ms = 100 requests in flight (size connection pools and queues for this)
  Little's law: 20,000 req/s x 200 ms = 4,000 requests in flight (size connection pools and queues for this)
ALL ASSERTIONS PASSED
```

* **A**: ~197 B/row of Python tuples (measured with tracemalloc) against 40–52 B/row in Arrow columns: ~18 GiB vs ~4–5 GiB for 100M rows.
* **B**: per-event CPU cost × rate = cores, and the per-row constants come from Folder 04's measurements.
* **C**: weight bytes by format, KV bytes per token, the bandwidth ceiling on batch-1 decode, 6ND for training compute, and all-reduce time from bus bandwidth. Each line names its assumptions.
* **D**: queueing delay is ρ/(2μ(1−ρ)) for deterministic service: 2 ms at 80 % and 49.5 ms at 99 % for a 1 ms service. Little's law sizes pools and queues.

---

## 3. Production Failure Modes & Debugging

Interview failure modes, which are also design-review failure modes:

| # | Symptom in the answer | What the interviewer hears | Fix |
|---|---|---|---|
| F1 | "Use Spark/Polars/Ray" with no mechanism | Tool familiarity, not understanding | Name the resource and the mechanism first |
| F2 | No numbers | Can't size or prioritize | Napkin math with stated assumptions (§2) |
| F3 | One option | No judgment | Two or three options with their costs |
| F4 | "Zero copy end to end", "GPUs are always faster" | Overclaiming | Copy ledgers (08.1 §1.2); measured counterexamples (05.3: 1.4× GPU for GBDT) |
| F5 | Ignoring correctness under scale | Duplicates, leakage, races go unnoticed | Integrity checks, parity tests, leakage-safe validation |
| F6 | Proposing rewrites first | Cost blindness | Measure, then fix the bottleneck in place |
| F7 | Ignoring operations | Pager-unfriendly designs | Cold start, restarts, skew, observability, rollback |
| F8 | Platform-blind claims | Works on one OS/build only | State platform assumptions (this KB's ⚠ items) |

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "A Python ETL job needs 40 GB of RAM for a 4 GB CSV."</b></summary>

**Initial Prompt.** A nightly job reads a 4 GB CSV with `csv.reader` into a list of dicts, then aggregates. It OOMs on 32 GB nodes.

**L5 Answer.** "Python has memory overhead; use a bigger machine."

**Why L5 Crashes at Scale.** It accepts a 10× blow-up as inherent and buys hardware that the next data growth step defeats. The overhead has a specific, removable cause.

**L7 Principal Defense.** Every field became a boxed object. A dict per row adds a hash table, and each int is 32 B, each float 24 B, each short string ~50–70 B. Measured: even compact tuples cost ~197 B/row against 40–52 B/row in Arrow columns (§2 A; ints are 32 B, 01.1). Fix by never materializing rows. Use a lazy columnar scan (Polars `scan_csv` / DuckDB `read_csv`) with projection and filters pushed down, aggregate in the engine, and convert the source to Parquet once so later runs read only the needed columns (03.2: lazy scan ~10× faster and ~8× less memory than eager-then-filter). Validate with peak RSS in a child process (03.2's method). Expect a single-digit-GB peak, bounded by the aggregation's state rather than the input size.

</details>

<details><summary><b>Q2 · "Our Python API has 50 ms latency spikes every few seconds."</b></summary>

**Initial Prompt.** A Flask/FastAPI service holding a large in-memory cache shows periodic p99 spikes with no traffic change.

**L5 Answer.** "Network jitter. Add retries."

**Why L5 Crashes at Scale.** Retries amplify load during the spikes. Periodic spikes in a process with a big object graph usually mean the cyclic garbage collector traversing it.

**L7 Principal Defense.** CPython's cyclic GC walks container objects in each generation; a full collection is proportional to the number of tracked objects (01.1 measured pause ∝ heap). Note that 3.14.0–3.14.4 shipped an incremental GC and 3.14.5 reverted to generational, so the patch version matters. Confirm with `gc.callbacks` timing and `gc.get_stats()` correlated with latency. Fixes: `gc.freeze()` after warm-up moves the long-lived cache to a permanent generation that isn't scanned (and helps pre-fork CoW); keep caches in non-container forms (NumPy/Arrow buffers, which have one tracked object); tune thresholds; or move the cache out of process. Validate with p99 before and after under the same replayed load.

</details>

<details><summary><b>Q3 · "Our Java team ported a thread-pool design to Python and got no speedup."</b></summary>

**Initial Prompt.** 16 worker threads parse and score records in pure Python; throughput equals one thread.

**L5 Answer.** "Python threads are broken; use asyncio."

**Why L5 Crashes at Scale.** asyncio is also single-threaded for Python bytecode. The cause is the GIL: one thread executes bytecode at a time (measured 0.98–1.15× of one thread for 4 CPU-bound threads, 01.2), and asyncio doesn't change that.

**L7 Principal Defense.** Classify the work. Python bytecode needs processes (ProcessPoolExecutor, or multiprocessing with shared memory for large inputs) or vectorization into native code. Native code that releases the GIL (NumPy, Arrow, compression, most I/O) parallelizes with threads (01.2's CDLL control). Free-threaded 3.14t removes the GIL, at an ABI and ecosystem cost (08.2 Q6). For record scoring, the L7 move is usually batching records into arrays and scoring vectorized, with no per-record Python at all, which beats 16 processes on cost too.

</details>

<details><summary><b>Q4 · "An asyncio service's latency degrades when one endpoint does CPU work."</b></summary>

**Initial Prompt.** One endpoint computes a 50 ms CPU-bound score; every other endpoint's p99 jumps.

**L5 Answer.** "Wrap it in `asyncio.to_thread`."

**Why L5 Crashes at Scale.** `to_thread` moves the call off the loop thread, but the worker thread still holds the GIL while running bytecode, so the loop thread gets the GIL only at switch intervals. Measured in 01.3: p99 ~48–59 ms with `to_thread` vs ~72–76 ms inline. Better, but still starved.

**L7 Principal Defense.** CPU-bound Python belongs in a **process pool** (measured ~1 ms p99 for other endpoints, 01.3) or in vectorized native code that releases the GIL. Measure event-loop lag directly (a probe coroutine) and alert on it. On Windows the loop's timer granularity (~15.6 ms, 07.3) also distorts timeouts, so measure there rather than assume. Separate CPU-heavy endpoints into their own deployment if they have different scaling needs.

</details>

<details><summary><b>Q5 · "Move 1 GB arrays between Python processes efficiently."</b></summary>

**Initial Prompt.** A pipeline passes large NumPy arrays between stages in separate processes via `multiprocessing.Queue`.

**L5 Answer.** "Queues pickle the data; that's fine."

**Why L5 Crashes at Scale.** Pickling copies 1 GB at least twice (serialize, deserialize), plus the pipe transfer: hundreds of milliseconds and 2–3× peak memory per handoff (01.3's IPC matrix).

**L7 Principal Defense.** Share memory and pass names or handles. Use `multiprocessing.shared_memory` with `np.frombuffer` views (zero copy), or Arrow IPC files memory-mapped by readers, or Ray's object store (`ray.get` of 16–512 MiB arrays ~0.3 ms as read-only views, 04.3). Mind lifetimes: in NumPy 2.5.4, `np.ndarray(buffer=shm.buf)` doesn't pin the buffer, so `close()` unmaps it under a live array and the next read crashes (reproduced, 01.3); `np.frombuffer` holds an export and is safe. Define ownership (who unlinks), make views read-only, and test the crash path.

</details>

<details><summary><b>Q6 · "This NumPy code uses 10× the memory of its input."</b></summary>

**Initial Prompt.** A feature computation `((x - x.mean(0)) / x.std(0)) ** 2 * w` on a 4 GB array OOMs at 40 GB.

**L5 Answer.** "Process it in chunks."

**Why L5 Crashes at Scale.** Chunking works but hides the mechanism. Each operator allocates a full-size temporary, broadcasting can silently produce an outer-product-sized intermediate, and dtype promotion may upcast to float64 (NEP 50 rules, 02.1).

**L7 Principal Defense.** Count temporaries: every binary op returns a new array, so an expression of k ops holds up to k full-size arrays at peak. Fix in order. Check dtypes (stay float32, watch NEP 50 promotion). Use in-place ufuncs with `out=` and reuse buffers. Use `numexpr` or `torch.compile` style fusion to evaluate the whole expression in one blocked pass (02.2 measured eager vs blocked vs fused). Check broadcasting shapes before running: a `(n,1) - (1,n)` pattern is n² memory. Chunk by blocks that fit in cache only after that. Validate with tracemalloc peak and a shape/dtype assertion at function entry.

</details>

<details><summary><b>Q7 · "Design a zero-copy interchange between a C++ engine and Python."</b></summary>

**Initial Prompt.** Your team's C++ query engine must hand results to pandas, Polars and PyTorch without serialization.

**L5 Answer.** "Expose a function that returns a NumPy array."

**Why L5 Crashes at Scale.** NumPy covers only fixed-width, non-null, single-buffer data. Strings, nulls, nested types and multi-chunk results need copies or custom conversions per library, and lifetime ownership across the boundary becomes ad hoc and unsafe.

**L7 Principal Defense.** Implement the **Arrow C Data Interface**. `ArrowSchema` (72 B) and `ArrowArray` (80 B) structs describe buffers (validity bitmap, offsets, values) with a `release` callback that transfers ownership exactly once (02.3 builds a C consumer). Expose it through PyCapsules (`__arrow_c_array__` / `__arrow_c_stream__`), and every Arrow-aware library imports it without copying (02.3: address proofs across pyarrow, Polars, DuckDB, pandas 3 and NumPy). For tensors, also export DLPack. Specify alignment (64 B), immutability and the stream protocol for large results, and test release semantics under exceptions.

</details>

<details><summary><b>Q8 · "String columns make our dataframe pipeline 5× slower and 3× larger."</b></summary>

**Initial Prompt.** A pandas pipeline over 50M rows with several text columns.

**L5 Answer.** "Strings are slow in Python; convert them to categories."

**Why L5 Crashes at Scale.** Categories help low-cardinality columns only. High-cardinality IDs and free text stay object columns: one Python `str` per cell (~50–70 B plus an 8 B pointer) and per-element Python calls.

**L7 Principal Defense.** Use Arrow-backed strings. pandas 3's default `str` dtype is Arrow-backed (03.1 measured RAM at ~1.4× the CSV size vs ~3.4× for object) and string ops run in C++. Polars stores Utf8View: 16-byte views with short strings inline (02.3), fast for comparisons and filters. Dictionary-encode low-cardinality columns. For ML, turn strings into integer IDs upstream (08.1 F6). Know the conversion costs: Arrow large_string → Polars Utf8View re-encodes (~30–40 ms per 20M rows, 02.3), and pandas `to_numpy` on strings materializes objects.

</details>

<details><summary><b>Q9 · "Does NumPy use AVX-512 on our new servers?"</b></summary>

**Initial Prompt.** Procurement bought AVX-512 CPUs expecting faster NumPy.

**L5 Answer.** "Yes. NumPy uses the best instructions available."

**Why L5 Crashes at Scale.** It depends on the build. NumPy dispatches at run time among kernels compiled into the wheel. If the wheel wasn't built with AVX-512 targets, they don't exist to dispatch to. Measured: the PyPI NumPy 2.5.4 Windows wheel dispatched only to x86-64-v3 (AVX2/FMA) (02.2).

**L7 Principal Defense.** Check `np.show_runtime()` and `__cpu_dispatch__` on the target build and benchmark ns/element for the hot ufuncs. Many workloads are bandwidth-bound anyway (02.1's stride and bandwidth measurements), so wider SIMD helps little there. The levers are memory traffic (fusion, float32) and threads in BLAS/engine code. If AVX-512 matters (compute-bound transcendental math), use builds or libraries that target it (some distribution builds, Intel's oneMKL paths for BLAS), measured per workload.

</details>

<details><summary><b>Q10 · "Pick an engine for a 200 GB daily batch on one 64-core box."</b></summary>

**Initial Prompt.** Joins and aggregations over 200 GB of Parquet; the result is 5 GB.

**L5 Answer.** "Spark, because 200 GB is big data."

**Why L5 Crashes at Scale.** On one box, Spark adds JVM and shuffle overhead without adding hardware. It may be right for the organization, but not for this job's cost.

**L7 Principal Defense.** Use a single-node vectorized engine with out-of-core execution. DuckDB spills joins and aggregates to disk under `memory_limit` (03.3 measured spilling vs OOM with temp_directory disabled). Polars streaming bounds data in flight, but not high-cardinality operator state (03.2: 731 → 303 MiB for 8 keys, no gain for 3M keys). Plan with pushdown (read only needed columns and row groups), sort/cluster inputs by filter keys, and size memory for the largest hash state. Choose DuckDB for SQL-heavy spilling joins, Polars for dataframe-style transformations; pandas 3 for interactive work on the 5 GB result. Validate with peak RSS and wall time on a representative day, and keep Spark for when data outgrows one node or must join an existing cluster workflow.

</details>

<details><summary><b>Q11 · "A selective filter still reads every Parquet row group."</b></summary>

**Initial Prompt.** `WHERE user_id = 42` scans 100 % of the data.

**L5 Answer.** "Add an index."

**Why L5 Crashes at Scale.** Parquet has no secondary indexes. Pruning relies on per-row-group min/max statistics, which only prune when values are **clustered**. Randomly distributed keys put every key's range in every row group.

**L7 Principal Defense.** Inspect the statistics (`pq.ParquetFile(...).metadata`, DuckDB `EXPLAIN ANALYZE` pruning counters, 03.3). Fix the layout: sort or cluster by the filter column when writing (Iceberg sort orders, Delta Z-order), and partition by low-cardinality columns. Beware parallel writers: DuckDB's parallel `PARTITION_BY` COPY interleaved rows so 2–4 of 4 row groups were scanned, against 1 of 4 with a sorted single-writer layout (03.3). Bloom filters help point lookups on high-cardinality columns. Validate with bytes-read metrics before and after.

</details>

<details><summary><b>Q12 · "The same as-of join gives different answers in Polars and pandas."</b></summary>

**Initial Prompt.** A trade/quote join for features disagrees on 0.3 % of rows between engines.

**L5 Answer.** "One of the libraries has a bug."

**Why L5 Crashes at Scale.** The difference is usually semantics, not bugs: ties on the join key, unsorted input, `allow_exact_matches`, the direction, and per-group sortedness. Features silently differ between training (one engine) and serving (another).

**L7 Principal Defense.** Define the semantics explicitly: strictly increasing timestamps per key (tie-break by sequence number), direction, tolerance and exact-match handling. Then enforce them: sort and validate, or pass explicit flags (03.4 needed tie-free keys and `check_sortedness=False` once sortedness was guaranteed). Write a cross-engine parity test on generated data with ties and gaps, which is how 03.4 asserts three engines agree. Use one implementation for training and serving where possible.

</details>

<details><summary><b>Q13 · "Which memory profiler tells the truth for a dataframe pipeline?"</b></summary>

**Initial Prompt.** tracemalloc reports 200 MB; the container is OOM-killed at 8 GB.

**L5 Answer.** "tracemalloc is accurate; the container limit is wrong."

**Why L5 Crashes at Scale.** tracemalloc sees only allocations through Python's allocator. Arrow (C++), Polars (Rust), DuckDB and NumPy's large buffers use their own allocators, so they're invisible to it (03.4 measured which tool sees which allocation).

**L7 Principal Defense.** Match the tool to the allocator. Use RSS/USS from psutil for the process truth (USS for what's unique to a worker). Use `pa.total_allocated_bytes()` for Arrow, DuckDB's memory views, `df.estimated_size()` for Polars, and `memory_usage(deep=True)` for pandas (shallow is misleading for object columns). Use tracemalloc for Python-object growth (it also costs ~58 B per live trace). Measure peaks in a child process per strategy (03.2's method). For containers, budget peak USS plus page cache behaviour. Memory-mapped Parquet pages show up in RSS but are reclaimable.

</details>

<details><summary><b>Q14 · "Our PySpark job is 20× slower than the Scala version."</b></summary>

**Initial Prompt.** Same logic; the Python version uses UDFs for feature transformations.

**L5 Answer.** "Python is slower than Scala; rewrite in Scala."

**Why L5 Crashes at Scale.** The DataFrame API in Python compiles to the same JVM plan. Only UDFs run in Python, through a separate worker process with serialization per batch. A rewrite is unnecessary if the UDFs are replaced or vectorized.

**L7 Principal Defense.** Find the Python nodes in the physical plan (`BatchEvalPython`, `ArrowEvalPython`). Replace UDFs with built-in expressions wherever possible (JVM ~5 ns/row), then with Arrow-based UDFs (`pandas_udf` ~53–60 ns/row, Arrow row UDF ~90–130), never pickled ones (~365–400 ns/row; measured in 04.1, where Spark 4.2 makes plain `@udf` Arrow-optimized by default). Use `mapInArrow` for batch-level logic. Check worker reuse, Arrow batch size and executor Python memory. On the measured Windows setup a fixed ~4–5 s per query also dominated small jobs, so measure marginal cost per row, not total time.

</details>

<details><summary><b>Q15 · "Run model inference inside a Beam pipeline at 10k elements/s."</b></summary>

**Initial Prompt.** A Dataflow job loads a PyTorch model in `process()` and scores one element at a time.

**L5 Answer.** "Increase the number of workers."

**Why L5 Crashes at Scale.** Loading the model per element (or per bundle) dominates, and one-at-a-time inference wastes the accelerator. More workers multiply both costs.

**L7 Principal Defense.** Load once per worker in `setup()` (DoFn lifecycle, 04.2), batch with RunInference or batched DoFns, and keep batches flowing end to end. 04.2 measured that batched DoFns win (~4.3×) only when batches flow through consecutive transforms, and that a Reshuffle costs ~20–30 µs per element. Share the model across threads in a process (one copy), size batches to the accelerator, and avoid Reshuffles in the hot path. Validate elements/s per worker and model-load counts from worker logs (setup/teardown metrics aren't reported, 04.2).

</details>

<details><summary><b>Q16 · "Why is `ray.get` of a 512 MiB array only 0.3 ms?"</b></summary>

**Initial Prompt.** A candidate claims Ray's object store is zero-copy. Prove or refute.

**L5 Answer.** "Ray compresses the data."

**Why L5 Crashes at Scale.** Misunderstanding the mechanism leads to mutating shared objects (which fails) or re-putting large objects per call (the slow path).

**L7 Principal Defense.** Ray's object store keeps objects in shared memory per node. `ray.get` of a NumPy array returns a **read-only view** of that memory (measured ~0.3 ms flat from 16 to 512 MiB, 04.3), and workers on the node read the same pages (private memory stayed ~96 MiB per worker for a 256 MiB shared array). Passing by reference (`ObjectRef`) avoids re-putting; passing a large array by value to every task call re-serializes it each time. Cross-node access copies over the network. Design: put once, pass refs, keep objects immutable, and watch object-store capacity and spilling.

</details>

<details><summary><b>Q17 · "Design the table format for a reproducible ML training set."</b></summary>

**Initial Prompt.** Model audits require regenerating exactly the data used for any past training run.

**L5 Answer.** "Copy the training data to a dated folder each run."

**Why L5 Crashes at Scale.** Full copies per run multiply storage, and folders give no atomic commits, schema history or concurrent-writer safety.

**L7 Principal Defense.** Use a table format with snapshots: Iceberg or Delta (04.4 executed snapshots, manifest pruning, deletes, schema evolution, time travel, compaction and vacuum). Record the table's snapshot ID (or version) in the training run's metadata, and read with time travel to reproduce. Retention policy must keep snapshots (and their files) as long as audits require, so vacuum and expire-snapshots have to respect it. Store features in the zero-copy layout (08.1 Q5), compact small files, and sort for pruning. Validate by re-reading a past snapshot and checking row counts and checksums against the run's record.

</details>

<details><summary><b>Q18 · "Offline AUC is 0.97; production performance is near random."</b></summary>

**Initial Prompt.** A fraud model's offline metrics collapsed after deployment.

**L5 Answer.** "Concept drift; retrain more often."

**Why L5 Crashes at Scale.** A gap that large on day one is almost always **leakage** in the offline evaluation, not drift. Retraining on leaky features reproduces the same fiction.

**L7 Principal Defense.** Audit the validation design. Temporal data needs time-ordered splits (05.1 measured KFold 0.973 vs TimeSeriesSplit 0.503 on the same data). Group leakage needs GroupKFold. Target encoding must be cross-fitted (05.2: a naive encoder's train/test gap was 0.145 vs 0.038 cross-fitted). Feature selection must happen inside the CV folds (05.1: selection on noise reached 0.845 accuracy). Fit all preprocessing inside a Pipeline. Then check feature availability at prediction time (point-in-time correctness) and training/serving parity on logged requests.

</details>

<details><summary><b>Q19 · "Our imbalanced classifier's probabilities are badly miscalibrated."</b></summary>

**Initial Prompt.** A 1 %-positive problem; downstream systems use the scores as probabilities for pricing.

**L5 Answer.** "Use `class_weight='balanced'`."

**Why L5 Crashes at Scale.** Class weighting optimizes ranking under a reweighted distribution and inflates probabilities: measured mean predicted probability 0.088 vs a base rate of 0.011 (05.2). The ranking (ROC-AUC) looks fine, but the pricing is wrong by ~8×.

**L7 Principal Defense.** Separate ranking from calibration. Train without weights, or undersample negatives and apply prior correction (05.2: best calibration, ~20× faster training). Then calibrate on a held-out set (isotonic or Platt) and monitor calibration curves and expected calibration error in production. Choose thresholds from business costs on PR curves, not 0.5. Report PR-AUC alongside ROC-AUC for rare positives.

</details>

<details><summary><b>Q20 · "Serve a GBDT model at 20 µs p50 per request."</b></summary>

**Initial Prompt.** A LightGBM model behind a Python service has p50 ~250 µs.

**L5 Answer.** "Rewrite the service in C++."

**Why L5 Crashes at Scale.** The model is already C++. The time goes to per-call Python overhead in the native predict path and in scikit-learn wrappers.

**L7 Principal Defense.** Export to ONNX and serve with ONNX Runtime: 05.3 measured single-row p50 ~26–30 µs for LightGBM (vs ~45–49 µs native) and ~13–16 µs for a scikit-learn pipeline (vs ~220–255 µs). Use one session per process, `intra_op_num_threads=1`, and scale with processes. Patch exporter quirks (05.3: onnxmltools declared a static `[1]` label dimension) and run golden-file parity tests with float32 tolerance. For batch scoring, throughput matters more than latency, and native batch predict is competitive.

</details>

<details><summary><b>Q21 · "Walk through `loss.backward()` on a GPU, end to end."</b></summary>

**Initial Prompt.** Explain every layer between the Python call and updated gradients.

**L5 Answer.** "It computes gradients with the chain rule."

**Why L5 Crashes at Scale.** Without the execution model you can't debug memory (saved tensors), performance (launch overhead, sync points) or distributed behaviour (DDP hooks).

**L7 Principal Defense.** Forward recorded a graph of `Node`s with saved tensors and version counters (06.2). `backward()` builds a GraphTask, counts dependencies, and schedules nodes on per-device ReadyQueues (ordered by sequence number). The CUDA worker thread runs each node's backward, whose ATen ops go through the dispatcher (06.1) and launch kernels asynchronously into the stream. `InputBuffer`s sum fan-in gradients, `AccumulateGrad` adds into `.grad`, saved tensors are released as nodes finish, and DDP's hooks launch bucketed all-reduces as gradients become ready (07.1). Nothing synchronizes with the host unless you call `.item()` or similar. Memory peaks at the start of backward: activations, plus gradients being created.

</details>

<details><summary><b>Q22 · "Training got 30 % slower after a refactor that only reshaped tensors."</b></summary>

**Initial Prompt.** A PR replaced `.view` with `.reshape` and added `permute`s for readability.

**L5 Answer.** "Reshapes are free; look elsewhere."

**Why L5 Crashes at Scale.** `reshape` silently copies when strides don't allow a view, and permuted tensors fed to many kernels force `.contiguous()` copies, with transposing copies running at half bandwidth (06.1: ~62–64 vs ~130–160 GB/s).

**L7 Principal Defense.** Profile for copy kernels (`copy_`, `contiguous`, `clone`) and memory deltas around the changed lines. Assert `is_contiguous()` or use `view` where a copy would be a bug. Choose layouts once (`channels_last` end to end: 1.35–1.5× faster fp16 convolutions measured; transpose weights at load time rather than activations each step). Let `torch.compile` fold layout changes into consumers. Add a perf regression test (step time on a fixed shape) to CI so layout refactors can't land silently.

</details>

<details><summary><b>Q23 · "When is `torch.compile` not worth it?"</b></summary>

**Initial Prompt.** A team wants to mandate `torch.compile` for every model.

**L5 Answer.** "Always compile; it's free speed."

**Why L5 Crashes at Scale.** Compilation costs seconds per graph per process (measured ~3.5–4.9 s for one tiny kernel cold, 06.3), recompiles with dynamic shapes (limit 8 per frame, then eager), and helps little where cuBLAS GEMMs dominate.

**L7 Principal Defense.** Decide by workload. Big wins: memory-bound pointwise and normalization chains (fused ~2.5× on a 4-op chain, matching the 2.75× traffic ratio) and launch-bound small batches with `reduce-overhead` (~1.4–1.7×). Little win: GEMM-dominated models (default mode ~1.0× on a launch-bound step). Risky: highly dynamic shapes, short-lived processes, autoscaled inference without warm caches. Mandate a measurement, not compile: compiled vs eager step time, compile count and time, numerical parity. Enable it where it wins, with `fullgraph=True` and recompile logging in CI.

</details>

<details><summary><b>Q24 · "Write the mixed-precision policy for our ML organization."</b></summary>

**Initial Prompt.** Teams use fp16, bf16 and fp32 inconsistently; some runs diverge.

**L5 Answer.** "Use bf16 everywhere."

**Why L5 Crashes at Scale.** Hardware differs (no bf16 tensor cores before Ampere), bf16's 8-bit mantissa breaks naive accumulation (`256 + 1 == 256`, 06.4), and some ops need fp32 regardless.

**L7 Principal Defense.** Defaults: bf16 autocast on Ampere and newer, fp16 + GradScaler on older GPUs (measured 100 % zero gradients without scaling vs 0 % with 65536, 06.4). Always fp32 for master weights, optimizer state, loss and softmax reductions (autocast's lists), and fp32 accumulation in custom kernels. TF32 for fp32 matmuls only by explicit opt-in (~2× throughput, 2.7e-4 relative error). Monitoring: loss-scale value and skipped steps, NaN/Inf detectors, a periodic fp32 evaluation pass. Expect ~1.8–2.0× step speedups (measured) at equal loss, and require a parity run when changing precision.

</details>

<details><summary><b>Q25 · "A long training run OOMs at step 10,000, not step 1."</b></summary>

**Initial Prompt.** Memory looks flat for hours, then an OOM with "X reserved but unallocated".

**L5 Answer.** "Lower the batch size."

**Why L5 Crashes at Scale.** It treats a fragmentation or leak signature as a capacity problem and permanently slows training.

**L7 Principal Defense.** Read the message: large "reserved but unallocated" means **fragmentation** (06.4). Growing allocated memory means a **leak**: tensors kept across steps, like `total_loss += loss` (06.2). Take a memory snapshot near the failure (`_record_memory_history`). For growth patterns (variable sequence lengths) use `expandable_segments:True` (measured 9 → 1 `cudaFree`, 3 → 1 retries). For interleaved lifetimes, allocate long-lived buffers first, pad shapes to buckets, and reuse preallocated buffers; expandable segments didn't fix interior holes in the measurement. Monitor `memory_allocated`, `memory_reserved` and `num_alloc_retries` per step.

</details>

<details><summary><b>Q26 · "Estimate the time and cost to pretrain a 7B model on 2T tokens."</b></summary>

**Initial Prompt.** Leadership wants a number by the end of the meeting.

**L5 Answer.** "A few weeks on a big cluster."

**Why L5 Crashes at Scale.** Unquantified estimates can't be budgeted or challenged, and they hide the efficiency assumption (MFU), which is the main uncertainty.

**L7 Principal Defense.** Training FLOPs ≈ 6·N·D = 6 × 7e9 × 2e12 = 8.4e22. At 40 % MFU of 989 TFLOP/s bf16 dense per H100 (assumed), that's ~59k GPU-hours: ~2.4 days on 1,024 GPUs (§2 C). Cost = GPU-hours × price. State sensitivities: MFU from 30 % to 50 % moves it by ±25 %; restarts and failures add 5–15 % (Q29); data pipeline or communication stalls lower MFU (07.1, 08.1). Validate with a short scaled run measuring tokens/s per GPU before committing the budget.

</details>

<details><summary><b>Q27 · "Choose the parallelism for a 13B model on 32 GPUs (4 nodes × 8)."</b></summary>

**Initial Prompt.** 80 GB GPUs, NVLink within nodes, InfiniBand across.

**L5 Answer.** "DDP across all 32."

**Why L5 Crashes at Scale.** DDP replicates 16 bytes/param of training state: 208 GB per GPU for 13B (§2 C). It doesn't fit.

**L7 Principal Defense.** Full sharding gives 6.5 GB/GPU of state across 32 ranks, leaving room for activations. Use FSDP2, or **HSDP**: shard within each 8-GPU node and replicate across nodes, which keeps the 3Ψ all-gather/reduce-scatter traffic on NVLink and leaves only a gradient all-reduce on InfiniBand (07.1). If activations are still too large at the target sequence length, add selective checkpointing (06.2) or TP = 2–4 inside nodes. Express it as a DeviceMesh, run a 1-step dry run per configuration recording peak memory and step time, and pick the cheapest one that fits with headroom.

</details>

<details><summary><b>Q28 · "Saving a sharded checkpoint takes 20 minutes every hour."</b></summary>

**Initial Prompt.** FSDP training gathers the full state dict on rank 0 and writes one file.

**L5 Answer.** "Checkpoint less often."

**Why L5 Crashes at Scale.** Less frequent checkpoints raise the expected lost work per failure (Q29), and rank-0 gathering also risks OOM (07.1 F4) while the other ranks wait.

**L7 Principal Defense.** Use sharded, parallel checkpointing. `torch.distributed.checkpoint` writes each rank's shards in parallel (aggregate storage bandwidth instead of one writer), supports resharding on load, and can stage to host memory and write asynchronously so training resumes in seconds. Size it: a 13B model with AdamW is ~208 GB of state; at 10 GB/s aggregate that's ~21 s, against minutes through one writer. Keep the last N checkpoints, verify integrity on save, and test restore-and-continue regularly.

</details>

<details><summary><b>Q29 · "Design fault tolerance for a 1,000-GPU, 3-week training job."</b></summary>

**Initial Prompt.** Hardware fails; the job must finish on time.

**L5 Answer.** "Checkpoint every hour and restart on failure."

**Why L5 Crashes at Scale.** At 1,000 GPUs failures are routine. If a GPU-node fails about once a year, 125 nodes produce a failure every ~3 days, and a fixed hourly cadence isn't derived from the failure rate or the checkpoint cost.

**L7 Principal Defense.** Compute the optimum. Young/Daly's interval ≈ √(2·C·MTBF): with C = 30 s (async sharded, Q28) and a job MTBF of ~70 h, checkpoint every ~1.1 h, losing on average half an interval per failure. Automate the restart path: health checks, an elastic launcher (`torchrun` with rendezvous) excluding bad nodes, hot spares, NCCL timeouts with flight-recorder dumps for hangs (07.1 Q8). Make the data loader resumable mid-epoch (08.1 F9). Track goodput (useful tokens / wall time) as the SLO.

</details>

<details><summary><b>Q30 · "Fine-tune and serve 50 domain variants of a 7B model cheaply."</b></summary>

**Initial Prompt.** Each business unit wants its own model; budget is one inference cluster.

**L5 Answer.** "Fine-tune 50 full copies and deploy them."

**Why L5 Crashes at Scale.** 50 × 14 GB of fp16 weights, 50 deployments, and full fine-tuning state (16 B/param = 112 GB per run) make it 50× the cost of one model for mostly shared knowledge.

**L7 Principal Defense.** Train LoRA adapters (1.56 % of parameters, 64× less optimizer state, exact merge, 07.2), or QLoRA on an NF4 base (4.127 bits/param, 3.6 GB for 7B) when GPU memory is tight. Serve one shared base with multi-adapter batching (S-LoRA/Punica style, ⚠ not run): requests for different adapters share the base matmuls, adapters are MBs each and cached hot on the GPU. Evaluate per-domain quality vs a full fine-tune on a few domains to bound the gap. Version adapters with their training data snapshot (Q17).

</details>

<details><summary><b>Q31 · "Our 128k-context deployment OOMs at a batch of 2."</b></summary>

**Initial Prompt.** A 7B model with 32 KV heads; weights fit easily.

**L5 Answer.** "Quantize the weights."

**Why L5 Crashes at Scale.** The KV cache dominates: 512 KiB per token × 128k tokens = 64 GiB per sequence (§2 C), so weight quantization (14 → 3.6 GB) is irrelevant. And if attention falls back to the MATH backend, the N² scores alone are impossible at this length (07.2 F6).

**L7 Principal Defense.** Reduce KV bytes. Use GQA/MQA models (the 70B GQA example is 320 KiB/token with 8 KV heads), an int8/FP8 KV cache (2×), paged KV allocation so memory follows actual lengths, and sliding-window or chunked attention where the model allows. Ensure tiled attention kernels (pin SDPA backends; FLASH wasn't available on the Windows build here). Then admission control by KV budget. Validate peak memory vs context length in a test, which should be linear, never quadratic.

</details>

<details><summary><b>Q32 · "Make 7B decode 3× faster per user."</b></summary>

**Initial Prompt.** Single-stream tokens/s is too low for an interactive product.

**L5 Answer.** "Use a bigger GPU."

**Why L5 Crashes at Scale.** Batch-1 decode is bandwidth-bound: tokens/s ≤ HBM bandwidth ÷ bytes read per token (all weights). A bigger GPU helps only in proportion to its bandwidth.

**L7 Principal Defense.** Cut bytes per token. int4 weights with a fused kernel raise the ceiling ~3.9× (239 → 928 tok/s on an assumed 3.35 TB/s GPU; the fused int4 kernel measured 2.5× over fp16 per layer on the laptop, 07.2), while naive dequant makes it slower. Remove launch overhead with CUDA Graphs per batch size (06.1, 06.3). Add speculative decoding (a draft model proposes tokens the big model verifies in one pass; ⚠ not run) to raise tokens per weight read. Keep throughput for many users with continuous batching (07.3). Validate tokens/s and quality per change.

</details>

<details><summary><b>Q33 · "Design online scoring at 100k QPS with p99 ≤ 30 ms."</b></summary>

**Initial Prompt.** Features from a store, a neural ranker, global traffic.

**L5 Answer.** "FastAPI behind a load balancer, autoscaled."

**Why L5 Crashes at Scale.** One Python process serves ~1–2.5k req/s (07.3), so 100k QPS means 50–100 processes each doing per-request Python work, each with its own model copy, with no batching and no queueing budget.

**L7 Principal Defense.** Size it. Little's law: 100k × 30 ms = 3,000 requests in flight. Keep utilization ≤ ~0.8 (queueing delay grows as ρ/(1−ρ), §2 D). Put a C++/JVM front end in front (parsing, auth, fan-out to the feature store with deadlines), then GPU scorers that batch greedily across requests (07.3: 6k/s at p99 ~2.5 ms from one GPU with a tiny model), with the model exported (ONNX/TensorRT/AOTInductor) so no Python runs per request. Budget the 30 ms: feature fetch p99, network, queue, compute. Shed load beyond capacity. Validate with open-loop load tests to the knee, per-stage latency histograms, and canaries (Q34).

</details>

<details><summary><b>Q34 · "Roll out a new model version safely."</b></summary>

**Initial Prompt.** The last model launch caused a revenue drop that took a week to detect.

**L5 Answer.** "A/B test it."

**Why L5 Crashes at Scale.** An A/B test without guardrails exposes users to a broken model for the test's duration, and slow business metrics detect regressions late.

**L7 Principal Defense.** Stage it. (1) Offline gates: leakage-safe validation (Q18), calibration (Q19), parity between exported and native models within tolerance (05.3). (2) Shadow traffic: the new model scores real requests without serving them, compared on prediction distributions, latency and errors. (3) A canary at 1–5 % with automated rollback on fast guardrail metrics (latency SLO, error rate, prediction drift, calibration). (4) A/B for the business metric, with pre-registered duration and power. Keep the previous version warm for instant rollback, and log features and predictions for replay.

</details>

<details><summary><b>Q35 · "Draw the end-to-end platform: JVM data, Python training, production serving."</b></summary>

**Initial Prompt.** You're the architect of an ML platform in a company whose data systems are JVM-based.

**L5 Answer.** "Spark for data, PyTorch for training, Kubernetes for serving."

**Why L5 Crashes at Scale.** A box diagram without contracts, data layouts, ownership or failure handling. It doesn't say how bytes move, how correctness is guaranteed, or how anything is debugged.

**L7 Principal Defense.** **Data plane**: Kafka → Flink/Spark (JVM) compute features once. Offline values go to an Iceberg/Delta table with snapshots (Q17) in the zero-copy schema (fixed-size list feature columns, sorted for pruning; 08.1 Q5), and online values to a feature store, with a parity test between the two. **Training**: Python reads snapshots through a streaming, sharded, zero-copy loader with integrity checks (08.1), runs FSDP/HSDP (07.1) with mixed precision (Q24) and sharded async checkpoints (Q28), and records data snapshot + code + environment lockfile per run (08.2 Q5). **Export**: ONNX / `torch.export` + AOTInductor (06.3 Q7), with parity tests. **Serving**: a C++/JVM front end, GPU batchers or Triton (07.3), KV-aware LLM engines where relevant (Q31), staged rollouts (Q34). **Contracts** are Arrow schemas and gRPC/Flight. **Observability**: loop lag, batch sizes, queue depth, GPU memory and allocator retries, data integrity checksums, model drift. **Ownership** follows the boundaries: JVM teams own the feature computation, ML teams own models, and platform owns the contracts and the paved road.

</details>

---

## 5. Invariants Checklist

- [ ] Every answer names the bottleneck resource and the mechanism one level down.
- [ ] Every estimate is derived (rates × costs, bytes × counts, 6ND, Little's law) with assumptions stated.
- [ ] Every design includes its failure modes, its validation and its operational signals.
- [ ] Every claim of "zero copy", "faster on GPU" or "free" carries a measured caveat or a ledger.
- [ ] Python orchestrates; native code computes. Most L7 answers move work across that boundary.

---

## 6. References

- J. Kaplan et al., "Scaling Laws for Neural Language Models", 2020 (the 6ND approximation) — https://arxiv.org/abs/2001.08361
- J. Hoffmann et al., "Training Compute-Optimal Large Language Models", 2022 — https://arxiv.org/abs/2203.15556
- J. W. Young, "A first order approximation to the optimum checkpoint interval", CACM 1974, DOI 10.1145/361147.361115
- J. T. Daly, "A higher order estimate of the optimum checkpoint interval for restart dumps", FGCS 2006, DOI 10.1016/j.future.2004.11.016
- J. D. C. Little, "A Proof for the Queuing Formula: L = λW", Operations Research 1961, DOI 10.1287/opre.9.3.383
- Y. Leviathan, M. Kalman, Y. Matias, "Fast Inference from Transformers via Speculative Decoding", 2022 — https://arxiv.org/abs/2211.17192
- PyTorch docs: distributed checkpoint (DCP) — https://docs.pytorch.org/docs/stable/distributed.checkpoint.html
- PyTorch docs: torchrun (elastic launch) — https://docs.pytorch.org/docs/stable/elastic/run.html
- Apache Iceberg spec (snapshots, time travel) — https://iceberg.apache.org/spec/
