# Python for Data, ML & Distributed Systems — L7 Reference

A first-principles knowledge base for a Staff/Principal backend and systems engineer (Java 21+, C/C++, SQL, Kafka, Beam/Dataflow) who wants to master Python's data, analytics and ML stack from the C runtime up: CPython internals, memory layout, zero-copy Arrow, vectorized engines, and PyTorch/GPU execution. It skips syntax tutorials. Every claim is either **measured by a listing that ships in the file**, **verified against pinned source**, or explicitly marked ⚠.

## Status

**All 8 folders complete (2026-10-29): 28 files, ~157k words, 80 verified listings, 264 Q&A chains; every folder gated (listings re-extracted from the KB and rerun) and link-checked.**

| # | Folder | Files | Status |
|---|---|---|---|
| 01 | [CPython Runtime, Memory Model & Concurrency Physics](01-CPython-Runtime-Memory-Model-and-Concurrency-Physics/) | 4 | ✅ **Done 2026-10-28**: ~34k words, 21 listings, 38 Q&A chains, gate passed, 66/66 URLs OK |
| 02 | [Scientific Computing Physics: NumPy & Apache Arrow](02-Scientific-Computing-Physics-NumPy-and-Apache-Arrow/) | 3 | ✅ **Done 2026-10-28**: ~18k words, 13 listings, 24 Q&A chains, gate passed, 33/33 URLs OK |
| 03 | [Data Analysis Engines: Polars, DuckDB & Pandas 3](03-Data-Analysis-Engines-Polars-DuckDB-and-Pandas-3/) | 4 | ✅ **Done 2026-10-28**: ~18.5k words, 11 listings, 32 Q&A chains, gate passed, 33/33 URLs OK |
| 04 | [Distributed Data Engineering: PySpark, Beam, Ray & Lakehouse](04-Distributed-Data-Engineering-PySpark-Beam-Ray-and-Lakehouse/) | 4 | ✅ **Done 2026-10-29**: ~15.9k words, 7 listings (real PySpark 4.2.1 on JDK 25, Beam 2.77, Ray 2.59, PyIceberg, delta-rs), 32 Q&A chains, gate passed, 37/37 URLs OK |
| 05 | [Classical ML Engineering: Scikit-Learn & GBDTs](05-Classical-Machine-Learning-Engineering-Scikit-Learn-and-GBDTs/) | 3 | ✅ **Done 2026-10-29**: ~11.5k words, 6 listings (incl. XGBoost on the RTX 3050), 24 Q&A chains, gate passed, 23/23 URLs OK |
| 06 | [Deep Learning Framework Internals: PyTorch 2 & GPU Physics](06-Deep-Learning-Framework-Internals-PyTorch-2-and-GPU-Physics/) | 4 | ✅ **Done 2026-10-29**: ~22.7k words, 10 listings (all on the RTX 3050, incl. Inductor-generated Triton kernels), 36 Q&A chains, gate passed, 40/40 URLs OK |
| 07 | [Distributed Training, Fine-Tuning & Production ML Systems](07-Distributed-Training-Fine-Tuning-and-Production-ML-Systems/) | 3 | ✅ **Done 2026-10-29**: ~19.9k words, 9 listings (real DDP/FSDP2 on gloo ranks, LoRA/NF4/attention on the GPU, FastAPI and Ray Serve under load), 27 Q&A chains, gate passed, 36/36 URLs OK |
| 08 | [Master Code Blueprints & FAANG L7 Interview Playbook](08-Master-Code-Blueprints-and-FAANG-L7-Interview-Playbook/) | 3 | ✅ **Done 2026-10-29**: ~15.8k words, 3 listings (end-to-end zero-copy Parquet → Polars/Arrow → PyTorch pipeline on the GPU, 16 Java-instinct traps, napkin math), 51 Q&A chains (incl. the 35-question playbook), gate passed, 25/25 URLs OK |

### Folder 01 files

1. [01 · `PyObject` C structs, refcounting, cyclic GC & `__slots__` memory math](01-CPython-Runtime-Memory-Model-and-Concurrency-Physics/01-pyobject-c-structs-refcounting-cyclic-gc-and-slots-memory-math.md)
2. [02 · GIL internals vs free-threaded 3.14t/3.15t, mimalloc & QSBR](01-CPython-Runtime-Memory-Model-and-Concurrency-Physics/02-gil-internals-vs-free-threaded-python-314t-315t-mimalloc-and-qsbr.md)
3. [03 · Concurrency matrix: threading, multiprocessing, shared memory, asyncio/uvloop](01-CPython-Runtime-Memory-Model-and-Concurrency-Physics/03-concurrency-matrix-threading-multiprocessing-shared-memory-and-asyncio-uvloop.md)
4. [04 · Descriptors, metaclasses, specialization, generators & Pydantic v2](01-CPython-Runtime-Memory-Model-and-Concurrency-Physics/04-advanced-object-model-descriptors-metaclasses-generators-and-pydantic-v2-rust.md)


### Files in Folders 02–08

- [02.1 · NumPy `ndarray` Internals: C vs Fortran Order, Strides, Views & Broadcasting Math](02-Scientific-Computing-Physics-NumPy-and-Apache-Arrow/01-numpy-ndarray-internals-c-vs-fortran-strides-views-and-broadcasting-math.md)
- [02.2 · Vectorization: SIMD ufuncs, the Buffer Protocol, `memoryview`, Numba & Cython](02-Scientific-Computing-Physics-NumPy-and-Apache-Arrow/02-vectorization-simd-ufuncs-buffer-protocol-memoryview-and-numba-cython.md)
- [02.3 · Apache Arrow: Columnar Memory Spec, Validity Bitmaps & Zero-Copy via the PyCapsule Interface](02-Scientific-Computing-Physics-NumPy-and-Apache-Arrow/03-apache-arrow-columnar-memory-spec-validity-bitmaps-and-zero-copy-pycapsule.md)
- [03.1 · pandas 3 Internals: PyArrow Backend, Mandatory Copy-on-Write & Index Pitfalls](03-Data-Analysis-Engines-Polars-DuckDB-and-Pandas-3/01-pandas-3-internals-pyarrow-backend-copy-on-write-and-index-pitfalls.md)
- [03.2 · Polars 2 Architecture: Rust LazyFrame, Query Optimizer & Streaming Out-of-Core Engine](03-Data-Analysis-Engines-Polars-DuckDB-and-Pandas-3/02-polars-2-architecture-rust-lazyframe-query-optimizer-and-streaming-out-of-core.md)
- [03.3 · DuckDB: In-Process OLAP, Vectorized Execution, Pushdown over Parquet & Arrow Integration](03-Data-Analysis-Engines-Polars-DuckDB-and-Pandas-3/03-duckdb-in-process-olap-vectorized-pushdown-over-parquet-and-arrow-integration.md)
- [03.4 · Data Wrangling Patterns: Window Functions, As-Of Joins, Dedup & Memory Profiling](03-Data-Analysis-Engines-Polars-DuckDB-and-Pandas-3/04-data-wrangling-patterns-window-functions-asof-joins-and-memory-profiling.md)
- [04.1 · PySpark Internals: JVM Driver → Python Worker Socket, Serialization & Arrow UDFs](04-Distributed-Data-Engineering-PySpark-Beam-Ray-and-Lakehouse/01-pyspark-internals-jvm-driver-to-python-worker-socket-serialization-and-arrow-udfs.md)
- [04.2 · Apache Beam Python SDK: Runner v2 Portability, DoFn Lifecycle, Batched DoFns & RunInference](04-Distributed-Data-Engineering-PySpark-Beam-Ray-and-Lakehouse/02-apache-beam-python-sdk-runner-v2-portability-dofn-lifecycle-and-runinference.md)
- [04.3 · Ray Architecture: Shared-Memory Object Store, Tasks & Actors, and Ray Data Streaming](04-Distributed-Data-Engineering-PySpark-Beam-Ray-and-Lakehouse/03-ray-architecture-plasma-shared-memory-object-store-actors-and-ray-data-streaming.md)
- [04.4 · The Modern Python Data Stack: Parquet Internals, PyIceberg, delta-rs, and dbt/Airflow](04-Distributed-Data-Engineering-PySpark-Beam-Ray-and-Lakehouse/04-modern-python-data-stack-parquet-internals-pyiceberg-deltalake-and-dbt-airflow.md)
- [05.1 · scikit-learn Architecture: the Estimator API, Pipelines & Preventing Data Leakage](05-Classical-Machine-Learning-Engineering-Scikit-Learn-and-GBDTs/01-scikit-learn-architecture-estimator-api-pipelines-and-preventing-data-leakage.md)
- [05.2 · Feature Engineering at Scale: Target Encoding, the Hashing Trick & Imbalanced Data](05-Classical-Machine-Learning-Engineering-Scikit-Learn-and-GBDTs/02-feature-engineering-at-scale-target-encoding-hashing-trick-and-imbalanced-data.md)
- [05.3 · Gradient-Boosted Trees: XGBoost, LightGBM, Histogram Binning & ONNX Serving](05-Classical-Machine-Learning-Engineering-Scikit-Learn-and-GBDTs/03-gradient-boosted-trees-xgboost-lightgbm-histogram-binning-and-onnx-serving.md)
- [06.1 · PyTorch Tensor Internals: Storage, Offset, Strides, Contiguity & the ATen Dispatcher](06-Deep-Learning-Framework-Internals-PyTorch-2-and-GPU-Physics/01-pytorch-tensor-internals-storage-offset-strides-contiguous-and-aten-dispatcher.md)
- [06.2 · The Autograd Engine: Dynamic Computation Graphs, Backward Hooks & Gradient Checkpointing](06-Deep-Learning-Framework-Internals-PyTorch-2-and-GPU-Physics/02-autograd-engine-dynamic-computation-graphs-backward-hooks-and-gradient-checkpointing.md)
- [06.3 · `torch.compile`: Dynamo Bytecode Capture, AOTAutograd, Inductor & Triton Kernels](06-Deep-Learning-Framework-Internals-PyTorch-2-and-GPU-Physics/03-torch-compile-dynamo-bytecode-capture-aotautograd-inductor-and-triton-kernels.md)
- [06.4 · GPU Execution Physics: CUDA Streams, Pinned Memory, DataLoader IPC & AMP/bf16](06-Deep-Learning-Framework-Internals-PyTorch-2-and-GPU-Physics/04-gpu-execution-physics-cuda-streams-pinned-memory-dataloader-ipc-and-amp-bf16.md)
- [07.1 · Distributed Training: DDP All-Reduce Rings vs FSDP/ZeRO Sharding & Tensor Parallelism](07-Distributed-Training-Fine-Tuning-and-Production-ML-Systems/01-distributed-training-ddp-allreduce-ring-vs-fsdp-zero-sharding-and-tensor-parallel.md)
- [07.2 · Parameter-Efficient Fine-Tuning: LoRA, QLoRA, Quantization & FlashAttention in PyTorch](07-Distributed-Training-Fine-Tuning-and-Production-ML-Systems/02-parameter-efficient-finetuning-lora-qlora-quantization-and-FlashAttention-in-pytorch.md)
- [07.3 · High-Throughput Python ML Serving: FastAPI, asyncio, Triton Server & Ray Serve](07-Distributed-Training-Fine-Tuning-and-Production-ML-Systems/03-high-throughput-python-ml-serving-fastapi-asyncio-triton-server-and-ray-serve.md)
- [08.1 · Master Blueprint: An End-to-End Zero-Copy Pipeline from Parquet through Polars/Arrow to a PyTorch DataLoader](08-Master-Code-Blueprints-and-FAANG-L7-Interview-Playbook/01-end-to-end-zero-copy-pipeline-parquet-to-polars-arrow-to-pytorch-dataloader.md)
- [08.2 · What a Java Backend Architect Must Master vs. Ignore in Python](08-Master-Code-Blueprints-and-FAANG-L7-Interview-Playbook/02-what-a-java-backend-architect-must-master-vs-ignore-in-python.md)
- [08.3 · 35 FAANG L7 Bar-Raiser Q&As: Python Data Engineering & ML Systems](08-Master-Code-Blueprints-and-FAANG-L7-Interview-Playbook/03-35-faang-l7-python-data-engineering-and-ml-systems-bar-raiser-qna.md)

## How each file is built

Every file follows the same spine (the gate enforces it):

- **§0 Orientation & the JVM/C++ Bridge**: a mapping table, so each Python mechanism lands on something you already know.
- **§1 First Principles**: C structs with offsets, pointer graphs, and execution flows, quoted from pinned CPython source.
- **§2 The Slow Pythonic Trap vs. the L7 Production Pattern**: complete runnable listings with their captured output.
- **§3 Production Failure Modes & Debugging**: a table of symptom → signature → root cause → fix → prevention, plus a toolkit.
- **§4 L7 Bar-Raiser Q&A Chains** (≥ 8 per file): *Initial Prompt → L5 Answer → Why L5 Crashes at Scale → L7 Principal Defense*.
- **§5 Invariants Checklist** and **§6 References**: pinned source links, PEPs and papers.

Tags: 🔥 production-critical · ⚡ performance lever · 🧊 Java/C++ bridge · ⚠ release-dependent or not executed here.
Outputs are labelled **"deterministic, verified"** (byte-identical on every rerun) or **"one measured run"** (numbers vary; prose quotes ranges seen across runs).

## Environment and pinned versions

| What | Version | How it was used |
|---|---|---|
| CPython (measured) | 3.14.5, python.org Windows x64, default (GIL) build, experimental JIT present | ran every Python listing |
| CPython (source) | tags `v3.14.10` and `v3.15.2` (sparse clones) | all struct layouts, constants and algorithms quoted |
| C toolchain | GCC 16.2 (MinGW-w64 UCRT), `-std=c11 -Wall -Wextra -Werror` | `pyobject_layout.c` (compiled against the real 3.14 headers, with and without `Py_GIL_DISABLED`), `spin.c`, `brc_physics.c` |
| Python packages | NumPy 2.5.4, pydantic 2.14.1 / pydantic-core 2.50.1, msgspec 0.22.0, psutil 7.2.2 | listings |
| PyTorch stack (06) | PyTorch 2.14.1+cu130, triton-windows 3.9.0.post30 (⚠ community Windows build of Triton, bundled TinyCC as `CC`); C++ headers from the wheel = tag `v2.14.1` | Folder 06 listings; struct fields and allocator constants quoted |
| Serving + distributed (07) | `torch.distributed` gloo (Windows wheels have no NCCL); FastAPI 0.162.0, Starlette 1.10.0, uvicorn 0.54.0, anyio 4.15.1, httpx 0.28.1 in `tools/py_serve`; Ray 2.59 Serve (+ grpcio, aiohttp) | Folder 07 listings |
| GPU | NVIDIA GeForce RTX 3050 Laptop GPU (Ampere GA107, sm_86, 16 SMs, 4 GB GDDR6), driver 610.78 (WDDM) | Folders 05–06 GPU timings ⚠ thermally throttles at ~84 °C |
| Hardware | Intel i5-11260H (Tiger Lake, 6C/12T), 16 GB, Windows 11 | all timings |

## Verification method

1. Listings live in a scratch harness and run sequentially (`f01.sh`, one process at a time).
2. Markdown templates splice in each listing's bytes and its captured output, so the KB text *is* the executed code.
3. The **gate** extracts every listing back out of the KB markdown, checks it's byte-identical to the source, rebuilds and reruns all of them from the extracted copies, and diffs the outputs. Deterministic outputs must match exactly; measured ones must match once digits are masked. It also checks the section spine, the four parts of every Q&A chain, fences and CRLF.
4. Every cited URL is fetched once; relative links are resolved.

Folder 01 gate: **21 listings byte-identical, 22 build/run steps OK from the KB copies, 5 outputs identical, 17 differ only in measured numbers. 66/66 URLs OK.**
Folder 02 gate: **13 listings, 12 steps (Cython and two C DLLs rebuilt from the KB copies), 2 identical, 10 measured. 33/33 URLs OK.**
Folder 03 gate: **11 listings, 11 steps (memory-sensitive strategies measured in child processes), 11 measured. 33/33 URLs OK.**
Folder 04 gate: **7 listings, 7 steps across four isolated framework environments (Spark on JDK 25, Beam, Ray, Iceberg/Delta), 1 identical, 6 measured. 37/37 URLs OK.**
Folder 05 gate: **6 listings, 6 steps (scikit-learn 1.9.1, XGBoost 3.4.1 CUDA, LightGBM 4.7, ONNX Runtime 1.31), 1 identical, 5 measured. 23/23 URLs OK.**
Folder 06 gate: **10 listings, 10 steps on the GPU with cold Inductor/Triton caches, 3 identical (autograd graph, Dynamo capture, allocator), 7 measured. 40/40 URLs OK.**
Folder 07 gate: **9 listings, 9 steps (multi-process gloo ranks, GPU, a uvicorn subprocess, a Ray Serve cluster), 2 identical (cost model, FSDP2), 7 measured. 36/36 URLs OK.** Prose ranges were re-synced after the gate and re-checked with `gate.py --static`.
Folder 08 gate: **3 listings, 3 steps, 2 identical (Java traps, napkin math), 1 measured. 25/25 URLs OK.** Ranges re-synced, `--static` re-check passed.

## What could not be executed here (and how it was covered)

- **Free-threaded CPython (3.14t/3.15t).** The PSF-signed `python-freethreaded` NuGet builds were downloaded and their Authenticode signatures verified, but this environment's safety policy refused to run a downloaded executable. Covered by compiling the real headers with `Py_GIL_DISABLED` (exact layouts), a C model of biased-refcount physics (`brc_physics.c`), and `ft_scaling_probe.py`, which prints a stated prediction for you to check by running it on `python3.14t`.
- **uvloop** (no Windows support) and the **Linux `fork`/`forkserver` start methods and `/dev/shm`**: explained from source and docs, and marked ⚠.
- **Folder 06**: Linux `fork` DataLoader copy-on-write growth (pytorch#13246) is explained, not reproduced; `tlparse`, `torch.export`/AOTInductor packaging, Triton GEMM autotuning (`max-autotune` needs a bigger GPU than 16 SMs) and GPU JPEG decode (nvJPEG/DALI) are explained, not run.
- **Folder 07**: no NCCL or multi-GPU (DDP/FSDP2 run as CPU gloo ranks; NVLink/InfiniBand numbers come from a stated cost model); NVIDIA Triton Inference Server, vLLM/PagedAttention, S-LoRA, GPTQ/AWQ and FP8 are explained, not run. LoRA, NF4 and the online-softmax attention are implemented from scratch instead of using `peft`/`bitsandbytes`.
- **dbt and Airflow** (04.4): explained, not executed. **Beam's Prism runner** was downloaded and run once by Beam's DirectRunner before this was noticed; the cache was deleted and all listings pin the pure-Python FnApiRunner.

## Where this KB refines the brief

These are places where measurement or pinned source contradicts or sharpens the original prompt:

1. **"10 M ints = 80 MB + 280 MB of 28-byte objects = 360 MB."** That's the `sys.getsizeof` view. One-digit ints are allocated as `sizeof(PyLongObject)` = **32 B** (struct padding, `_PyLong_FromMedium`). Measured: tracemalloc 32.0 B per int, **≈ 402 MB** of private bytes.
2. **"A normal instance allocates a `__dict__` hash table (~112+ B)."** Since 3.13 instances store **inline values** and have no dict until one is requested (96 B per 3-field instance against 56 B with `__slots__`). Touching `obj.__dict__` adds 64 B; more than 30 attribute names per class (`SHARED_KEYS_MAX_SIZE`) gives 320 B per instance.
3. **"CPU-bound threads run slower on multicore because of lock convoying."** That was the pre-3.2 GIL. On 3.14.5, four CPU-bound threads run at 0.98–1.15× of one. The convoy effect still exists, but it hits **I/O threads' latency** (≈ 35 ms round trips with one CPU hog).
4. **"5 ms switch interval."** On Windows the GIL wait is truncated to whole milliseconds and then rounded to the OS timer tick, so measured slices are **≈ 16 ms** for any setting from 1–15 ms, and intervals below 1 ms truncate to 0 (immediate handoffs).
5. **`_Py_IMMORTAL_REFCNT`.** In 3.14 the default build uses `_Py_IMMORTAL_INITIAL_REFCNT` (`3 << 30`) plus `ob_flags`; the free-threaded build uses `ob_ref_local == UINT32_MAX`. A runtime-interned string is **mortal** in 3.14 (measured).
6. **GC.** 3.14.0–3.14.4 shipped an incremental collector; **3.14.5 reverted to the generational GC** (gh-142516), and 3.15 keeps it. Patch versions matter.
7. **PEP 803 (`abi3t`) is a 3.15 feature**, not 3.14. 3.15.0 is released (current 3.15.2).
8. **Biased refcounting's slow path** isn't only "an atomic increment by other threads": negative shared counts queue the object to its owner for a merge (`Python/brc.c`), and hot shared objects use deferred and per-thread refcounting instead.
9. **Zero-copy shared memory has a lifetime trap.** With NumPy 2.5.4, `np.ndarray(buffer=shm.buf)` doesn't hold a buffer export, so `SharedMemory.close()` unmaps under it and the next read crashes (reproduced: `0xC0000005`). `np.frombuffer` is protected.
10. **`asyncio.to_thread` doesn't fix GIL starvation for Python bytecode** (p99 ≈ 48–59 ms against ≈ 72–76 ms inline; a process pool gives ≈ 1 ms).
11. **Type-version exhaustion.** A class mutated on a hot path more than `MAX_VERSIONS_PER_CLASS` (1000) times can never be specialized again in that process (`LOAD_ATTR` forever).
12. **Pydantic v2.** `model_construct` is slower than `model_validate_json` (pure Python, unvalidated), and a per-call `TypeAdapter` costs ~2.5×, not orders of magnitude, on pydantic 2.14.
13. **`arr.is_contiguous`** doesn't exist in NumPy (that's PyTorch). Use `flags.c_contiguous`, `np.shares_memory` and `base`. Assigning `arr.shape` is deprecated in NumPy 2.5; `np.reshape(..., copy=False)` is the no-copy assertion.
14. **"10 GB between DuckDB, Polars, pandas 3 and PyTorch in 0.01 ms"** holds only for null-free numeric columns whose consumer stores Arrow natively (measured ~3–70 µs, independent of size). Strings into Polars are re-encoded to Utf8View (~30–40 ms per 20 M rows), and pandas 3's default `to_pandas()`/`from_arrow()` copies numerics into NumPy (~100–130 ms). `types_mapper=pd.ArrowDtype` is zero-copy for every column, and pandas 3's default `str` columns keep Arrow's buffers.
15. **SIMD.** The PyPI NumPy 2.5.4 Windows wheel dispatches only to x86-64-v3 (AVX2/FMA); AVX-512 on the CPU goes unused by ufuncs.
16. **Polars per core.** Polars isn't faster per core on a hash group-by: single-threaded it measured 0.9× pandas. The win is the thread pool (3.7× on 12 threads), pushdown (lazy scan ~10× faster and ~8× less memory than eager read-then-filter), and no Python UDFs (`map_elements` ~60× slower).
17. **Streaming bounds data in flight, not operator state.** Polars streaming cut peak memory 731 → 303 MiB for an 8-key group-by, but did nothing for a 3M-key one (947 vs 968 MiB).
18. **Predicate pushdown needs clustered data.** DuckDB's default parallel partitioned `COPY` interleaved rows so row-group min/max ranges overlapped (2–4 of 4 scanned); a sorted single-writer layout scanned 1 of 4.
19. **pandas 3 CoW copies at column granularity.** The first write after a lazy method chain copied 15 MiB (one column), not the 153 MiB frame. `to_numpy()` / `.values` are read-only views.
20. **"Row UDFs pickle rows; Arrow UDFs are 20–50× faster"** needs updating. In Spark 4.2 a plain `@udf` is already Arrow-optimized by default (`ArrowEvalPython`). Measured marginal costs per row: JVM ~5 ns, pickled ~365–400 ns, Arrow row UDF ~90–130 ns, `pandas_udf` ~53–60 ns. On Windows a fixed ~4–5 s per query (Python workers spawned per task) dwarfs these at small sizes.
21. **Beam's DirectRunner** in 2.77 silently downloads and runs the Prism Go runner. The KB pins `FnApiRunner`. Beam batched DoFns win (~4.3×) only when batches flow end to end, and a Reshuffle costs ~20–30 µs per element.
22. **Ray zero copy, measured.** `ray.get` of a NumPy array is ~0.3 ms from 16 to 512 MiB (a read-only view). Workers reading a shared 256 MiB array stayed at ~96 MiB private each. Passing by value re-puts per call. Task overhead is ~200–255 µs.
23. **scikit-learn caching and threads.** `Pipeline(memory=...)` made a cheap-PCA grid search slower (1.15 → 1.50 s, input hashing) and helped only an expensive transformer. Nested joblib × OpenMP parallelism must be budgeted: 4 workers × 3 threads beat 4 × 12.
24. **Imbalance.** `class_weight="balanced"` kept ROC-AUC but inflated mean probability 8× (0.088 vs base 0.011). 10× undersampling + prior correction gave the best calibration and trained ~20× faster.
25. **GBDT on GPU.** On 500k × 30 the RTX 3050 trained XGBoost only ~1.4–1.5× faster than 12 CPU threads. ONNX Runtime served a scikit-learn pipeline 15–17× faster single-row than `predict_proba`, and onnxmltools' LightGBM export declares a static `[1]` label dim (patch it).
26. **"`x = sin(a) + cos(b) * c` reads/writes HBM 3 separate times."** Eager PyTorch runs 4 kernels and makes 11 tensor-sized DRAM passes; Inductor's single Triton kernel makes 4 (3 loads, 1 store). Measured ~2.5×, tracking the 2.75× traffic ratio.
27. **Pinned memory.** Pageable sources do force a synchronous CPU staging copy (`.to(non_blocking=True)` blocked ~32–42 ms vs ~0.07–0.09 ms from pinned), but the bandwidth gap on this Windows host was only 1.1–1.7×. The point of pinning is asynchrony, not speed.
28. **DataLoader memory isn't only a `fork` problem.** Under `spawn` (Windows/macOS) each worker costs ~386 MiB just for the runtime, and a list of 500k tuples that pickled to 7.5 MiB cost ~58–62 MiB more per worker once unpickled. The default `persistent_workers=False` re-spawns every epoch (4.2–5.6 s vs 0.7–1.0 s per epoch).
29. **`torch.utils.checkpoint` default.** 2.14.1 still warns and falls back to `use_reentrant=True` (`checkpoint.py` line 635), although the warning says 2.9 would raise. Per-block checkpointing cut held activations 6× for ~1.2–1.4× step time.
30. **`expandable_segments:True` isn't a general fragmentation fix.** It removed free-all-and-retry storms for a growing buffer (9 → 1 `cudaFree`, 3 → 1 retries) but didn't reclaim interior holes pinned by live tensors (OOM in both, even after `empty_cache()`).
31. **`torch.compile` on a launch-bound step.** Default mode gave ~1.0× on a batch-64 MLP training step (optimizer and launches dominate). `mode="reduce-overhead"` (CUDA Graphs) gave ~1.4–1.7×. Cold compile of one tiny kernel took ~3.5–4.9 s.
32. **gloo on Windows.** No NCCL. Bus bandwidth was ~0.45–0.9 GB/s with 3–4 localhost ranks, while exactly 2 ranks hit a 5–10× cliff above 256 KiB (cause not isolated ⚠). The profiler shows gloo executing every FSDP reduce-scatter as an `all_reduce`, about 2× the bytes.
33. **ZeRO arithmetic checks out.** 16 bytes/param mixed-precision AdamW reproduces the ZeRO paper's 120 / 31.4 / 16.6 / 1.9 GB (7.5B, 64 GPUs). FSDP2 shards parameters and AdamW state exactly 1/N, matches a single-process reference to 1e-6, and `reshard_after_forward=True` costs 8 vs 4 all-gathers per step on 4 layers.
34. **QLoRA storage, measured.** NF4 + double-quantized absmax = 4.127 bits/param (the paper's figure). On an exactly low-rank target, NF4's full-rank 9.2 % weight noise left a loss floor (1.5e-3 vs 1.0–1.5e-5 for LoRA on fp32). LoRA itself beat full fine-tuning there with 1.56 % of the parameters.
35. **"Quantized = faster" depends on the kernel.** Batch-1 GEMV: naive dequant-then-matmul was 5.7× *slower* than fp16 and `torch.compile` 2.5× slower, while PyTorch's fused int4 tinygemm kernel was 2.5× *faster*. int8 `torch._int_mm` ran at 0.7–0.9× fp16 on this Ampere GPU, not the datasheet 2×.
36. **SDPA backends.** The Windows wheel has no FLASH_ATTENTION kernel ("No available kernel"). EFFICIENT and CUDNN were ~27× faster than MATH with 4 MiB vs 1,248 MiB extra memory at N = 4096, so code that doesn't pin backends can silently fall back to O(N²).
37. **Windows asyncio timers.** `ProactorEventLoop` sleeps round to the ~15.6 ms tick (`sleep(1 ms)` = 16 ms, `wait_for(..., 2 ms)` = 23 ms), so a "2 ms" batching window becomes 16–23 ms. `timeBeginPeriod(1)` gives ~2–3 ms. Greedy batching needs no timer.
38. **Serving ceilings.** One FastAPI process with a greedy GPU batcher served 1.8–2.4k req/s (1.6–1.9× inline or threadpool endpoints). httpx's `AsyncClient` degraded above ~8 connections as a load generator. Ray Serve on one Windows node capped at ~150–200 req/s through the HTTP proxy and ~300–380 through handles, framework overhead above the 1 ms model.
39. **Zero copy is decided by the schema.** A FixedSizeList<float32>[16] feature column reached torch at the same address through Arrow and NumPy, while 16 scalar columns needed a 122 MiB transpose copy (~300–470 ms per 1M rows). The tensor layout was also smaller on disk (129 vs 181 MiB).
40. **Threads beat processes for Arrow-bound loaders on spawn platforms.** Parquet decode and Arrow filters release the GIL. A 2-thread prefetcher streamed 3.1–3.3M rows/s against 1.25–1.33M in-process and ~0.23M with 2 spawned workers, and the per-row pandas trap managed ~13–15k rows/s. The listing's first draft also reproduced the spawn re-import trap (module-level data generation re-ran in every worker).
41. **`sum()` isn't a loop.** Since 3.12 built-in `sum()` of floats is compensated (`sum([0.1]*10) == 1.0`), while a hand-written loop gives 0.9999999999999999, so two "equivalent" metric implementations can differ.

## Listing index — Folder 08

| Listing | File | Proves |
|---|---|---|
| `zero_copy_pipeline.py` | 08.1 | wide vs tensor Parquet layouts, Polars → Arrow → NumPy → torch address proofs, per-row trap vs streaming batches (in-process, processes, threads) with integrity checks, GPU step |
| `java_instinct_traps.py` | 08.2 | sixteen Java instincts that are wrong in CPython 3.14 (defaults, closures, identity, aliasing, overflow, hashing, hints, generators, truthiness, except, datetimes, sums) |
| `l7_napkin_math.py` | 08.3 | bytes per row, cores per event rate, LLM weight/KV/decode arithmetic, 6ND, all-reduce time, ZeRO memory, M/D/1 and Little's law |

## Listing index — Folder 07

| Listing | File | Proves |
|---|---|---|
| `collective_cost_model.py` | 07.1 | ring all-reduce simulation and bytes per rank, alpha-beta ring/tree/server model, ZeRO memory (paper check), Megatron column/row split |
| `ddp_gloo_processes.py` | 07.1 | gloo all-reduce cost vs size and world, DDP gradient equivalence, bucket counts, `no_sync`, DDP step cost on a slow link |
| `fsdp2_sharding.py` | 07.1 | DTensor shards and AdamW state per rank, equivalence vs one process, all-gather/reduce-scatter counts, reshard_after_forward |
| `lora_qlora_from_scratch.py` | 07.2 | LoRA vs full fine-tune (params, state, memory, time, loss), exact merge, NF4 + double quantization bits and QLoRA training |
| `quantization_error_speed.py` | 07.2 | int8/int4/NF4 error by granularity with outliers, batch-1 GEMV fp16 vs naive vs compiled vs fused int4, int8 GEMM throughput |
| `flash_attention_tiling.py` | 07.2 | naive attention memory vs N, exact online-softmax tiling, SDPA backends (availability, time, memory), traffic arithmetic |
| `asyncio_dynamic_batcher.py` | 07.3 | GPU cost vs batch, Windows timer granularity, open-loop load vs single / greedy / windowed batching |
| `fastapi_event_loop.py` | 07.3 | uvicorn + FastAPI: blocking `async def` vs threadpool `def` vs batched, event-loop health under load |
| `ray_serve_batching.py` | 07.3 | Ray Serve routes (single, 2 replicas, `@serve.batch`) via HTTP proxy and DeploymentHandles |

## Listing index — Folder 06

| Listing | File | Proves |
|---|---|---|
| `tensor_anatomy.py` | 06.1 | storage sharing table, `view` failure, contiguous vs transposing copy bandwidth, DLPack/NumPy bridges, channels_last |
| `dispatch_launch_overhead.py` | 06.1 | dispatch key sets, per-op CPU cost (NumPy vs torch vs autograd vs inference_mode), launch-bound loops, `.item()` syncs, CUDA Graphs |
| `autograd_graph.py` | 06.2 | grad_fn graph walk, saved-tensor byte accounting vs held memory, hooks, accumulation, version-counter and backward-twice errors |
| `activation_checkpointing.py` | 06.2 | memory held for backward and step time: none vs `checkpoint_sequential` vs per-block |
| `dynamo_graph_capture.py` | 06.3 | FX graph from a custom backend, graph breaks, guard failures and recompiles, AOTAutograd partitioners (min-cut rematerialization) |
| `inductor_fusion.py` | 06.3 | fused Triton kernel vs eager traffic, generated kernel source, compile vs reduce-overhead on a training step, cold compile cost |
| `h2d_pinned_streams.py` | 06.4 | pageable vs pinned bandwidth and blocking, two-stream overlap, async D2H race |
| `dataloader_workers.py` | 06.4 | worker scaling under `spawn`, persistent workers, per-worker USS for list vs NumPy datasets, `pin_memory` |
| `amp_mixed_precision.py` | 06.4 | format table, fp32/tf32/fp16/bf16 matmul TFLOP/s and error, overflow/rounding/underflow, AMP training runs |
| `cuda_allocator_fragmentation.py` | 06.4 | allocated vs reserved, pools and rounding, fragmentation OOM, expandable segments (holes vs growth) |

## Listing index — Folder 05

| Listing | File | Proves |
|---|---|---|
| `sklearn_leakage_lab.py` | 05.1 | selection bias on noise, temporal leakage, group leakage, and their fixes |
| `sklearn_pipeline_internals.py` | 05.1 | estimator contract and clone, ColumnTransformer + pandas output, caching regimes, nested-thread budget |
| `target_encoding_hashing.py` | 05.2 | one-hot vs hashing vs naive vs cross-fitted target encoding on a 50k-level feature |
| `imbalanced_metrics.py` | 05.2 | accuracy paradox, ROC vs PR-AUC, class weights vs undersampling, prior correction, calibration, thresholds |
| `gbdt_histogram_physics.py` | 05.3 | uint8 binning, sklearn HGB vs XGBoost CPU/CUDA vs LightGBM, max_bin, thread scaling |
| `onnx_serving.py` | 05.3 | ONNX export, parity, single-row latency and batch throughput vs native |

## Listing index — Folder 04

| Listing | File | Proves |
|---|---|---|
| `pyspark_udf_ladder.py` | 04.1 | JVM expression vs pickled / Arrow / pandas_udf / mapInArrow: fixed vs marginal cost, plan nodes, toPandas with Arrow |
| `beam_dofn_batching.py` | 04.2 | DoFn lifecycle per worker, element vs batch end to end, Reshuffle cost, in-process vs gRPC Fn API |
| `beam_runinference.py` | 04.2 | load-per-element vs setup vs RunInference batching |
| `ray_object_store_zero_copy.py` | 04.3 | put/get vs size, by-ref vs by-value, worker private memory, task/actor overhead |
| `ray_data_streaming.py` | 04.3 | `map` vs `map_batches` (numpy/pyarrow), streaming `iter_batches` |
| `parquet_internals.py` | 04.4 | codecs, encodings and statistics, sort order, row-group size vs filtered reads |
| `iceberg_delta_tables.py` | 04.4 | snapshots, manifest pruning, deletes, schema evolution, time travel, compaction, vacuum |

## Listing index — Folder 03

| Listing | File | Proves |
|---|---|---|
| `pandas3_cow_blocks.py` | 03.1 | CoW semantics, ChainedAssignmentError, lazy chains, column-granular copy, BlockManager fragmentation |
| `pandas3_strings_memory.py` | 03.1 | object vs `str` (Arrow) vs category: RAM/CSV ratio, parse time, string-op speed |
| `pandas_index_pitfalls.py` | 03.1 | alignment bugs, non-unique index lookups, row-wise ladder, transform vs apply |
| `polars_lazy_pushdown.py` | 03.2 | eager vs projected vs lazy scan (child-process peak RSS), optimized plan text |
| `polars_expressions_engine.py` | 03.2 | threads vs pandas, `map_elements` cliff, parallel `with_columns` |
| `polars_streaming_out_of_core.py` | 03.2 | eager vs in-memory vs streaming engines for high/low cardinality, `sink_parquet` |
| `duckdb_pushdown_parquet.py` | 03.3 | Hive partition and row-group pruning (EXPLAIN ANALYZE counters), parallel vs sorted layout |
| `duckdb_spill_threads.py` | 03.3 | thread scaling, `memory_limit` spilling vs OutOfMemoryException |
| `duckdb_arrow_udf.py` | 03.3 | result transfer (fetchall vs Arrow vs Polars vs pandas), native vs Arrow UDFs vs SQL |
| `window_asof_patterns.py` | 03.4 | as-of joins, rolling windows, latest-per-key across three engines (asserted equal) |
| `memory_profiling_toolkit.py` | 03.4 | which tool sees which allocation; tracemalloc's own overhead; shallow vs deep memory_usage |

## Listing index — Folder 02

| Listing | File | Proves |
|---|---|---|
| `ndarray_anatomy.py` | 02.1 | `PyArrayObject` fields off live arrays; view vs copy table; O(1) vs O(n) ops |
| `stride_cache_physics.py` | 02.1 | traversal order (10×), strided bandwidth (exact lines touched), blocked transpose |
| `broadcast_copy_traps.py` | 02.1 | temporaries, NEP 50 promotion, broadcast blow-up vs Gram/BLAS, `np.take` buffering, windows |
| `ufunc_simd_dispatch.py` | 02.2 | SIMD dispatch targets, ns/element, call overhead, pairwise vs sequential summation |
| `buffer_protocol_zero_copy.py` | 02.2 | shared addresses, export count, structured-dtype parsing, mmap views |
| `ewma_cy.pyx`, `ewma_c.c`, `kernels_numba_cython.py` | 02.2 | a recurrence six ways: Python, ndarray indexing, Numba, Cython, C, Numba parallel |
| `fusion_numexpr.py` | 02.2 | eager vs blocked vs fused evaluation, compute- vs memory-bound |
| `arrow_buffer_anatomy.py` | 02.3 | validity bitmaps, offsets, Utf8View, alignment, dictionary encoding |
| `arrow_consumer.c`, `arrow_c_data_interface.py` | 02.3 | C Data Interface structs, a C consumer, branchless nulls, release, PyCapsules |
| `pycapsule_zero_copy_exchange.py` | 02.3 | zero-copy matrix pyarrow↔Polars↔DuckDB↔pandas 3↔NumPy with address proofs |

## Listing index — Folder 01

| Listing | File | Proves |
|---|---|---|
| `pyobject_layout.c` | 01.1 (and 01.2) | `sizeof`/`offsetof` of object headers, default vs free-threaded |
| `pyobject_anatomy.py` | 01.1 | live struct overlay: refcounts, immortals, `lv_tag`, list growth, GC head |
| `int_storage_math.py` | 01.1 | 10 M ints: getsizeof vs tracemalloc vs RSS; shuffled-pointer scan |
| `slots_layout.py` | 01.1 | bytes per record ×9 representations; slot member offsets |
| `refcount_gc_physics.py` | 01.1 | refcount vs cycle GC, GC pause ∝ heap, `gc.freeze`, `del` pauses |
| `arena_fragmentation.py` | 01.1 | pymalloc arenas pinned by survivors |
| `spin.c`, `gil_release_scaling.py` | 01.2 | which work escapes the GIL (CDLL vs PyDLL control) |
| `gil_convoy.py` | 01.2 | convoy effect; measured GIL slices; Windows timer quantization |
| `gil_is_not_a_lock.py` | 01.2 | lost updates *with* the GIL |
| `brc_physics.c` | 01.2 | owner-local vs atomic vs contended vs immortal refcount cost |
| `ft_scaling_probe.py` | 01.2 | scaling probe for GIL and free-threaded builds |
| `cpu_bound_matrix.py` | 01.3 | threads vs processes vs subinterpreters |
| `ipc_cost_matrix.py` | 01.3 | pickle vs shared memory; the view-lifetime crash |
| `asyncio_loop_lag.py` | 01.3 | GIL starvation of an asyncio server |
| `asyncio_footguns.py` | 01.3 | task vs thread memory, eager tasks, GC'd tasks, debug mode, swallowed cancel |
| `attribute_lookup.py` | 01.4 | executable model of `PyObject_GenericGetAttr` |
| `specialization_jit.py` | 01.4 | PEP 659 rewrites, version-tag exhaustion, polymorphism, JIT on/off |
| `class_machinery.py` | 01.4 | class-creation hook order, descriptor bugs, access and `isinstance` costs |
| `generator_frames.py` | 01.4 | generator frames, streaming memory, int64 wraparound, pinned locals |
| `pydantic_v2_paths.py` | 01.4 | seven decode/validate paths, lax vs strict, bytes per instance |

## Related KBs in this workspace

- `Modern-Cpp-ABI-STL-Concurrency-L7-Reference`: `shared_ptr` refcount costs, memory orderings, and SMR/RCU (it backs the biased-refcount and QSBR comparisons here).
- `Unified-Dataflow-Beam-Flink-L7-Reference`: the Beam/Dataflow side of Folder 04.
- `Production-AI-Engineering-L7-Reference`: LLM serving, the downstream of Folders 06–07.
