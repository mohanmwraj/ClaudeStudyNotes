# Python for Data, ML & Distributed Systems — L7 Reference

A first-principles knowledge base for a Staff/Principal backend and systems engineer (Java 21+, C/C++, SQL, Kafka, Beam/Dataflow) who wants to master Python's data, analytics and ML stack from the C runtime up: CPython internals, memory layout, zero-copy Arrow, vectorized engines, and PyTorch/GPU execution. It skips syntax tutorials. Every claim is either **measured by a listing that ships in the file**, **verified against pinned source**, or explicitly marked ⚠.

## Status

| # | Folder | Files | Status |
|---|---|---|---|
| 01 | [CPython Runtime, Memory Model & Concurrency Physics](01-CPython-Runtime-Memory-Model-and-Concurrency-Physics/) | 4 | ✅ **Done 2026-10-28**: ~34k words, 21 listings, 38 Q&A chains, gate passed, 66/66 URLs OK |
| 02 | Scientific Computing Physics: NumPy & Apache Arrow | 3 | ⏳ next, on request |
| 03 | Data Analysis Engines: Polars, DuckDB & Pandas 3 | 4 | ⏳ |
| 04 | Distributed Data Engineering: PySpark, Beam, Ray & Lakehouse | 4 | ⏳ |
| 05 | Classical ML Engineering: Scikit-Learn & GBDTs | 3 | ⏳ |
| 06 | Deep Learning Framework Internals: PyTorch 2 & GPU Physics | 4 | ⏳ |
| 07 | Distributed Training, Fine-Tuning & Production ML Systems | 3 | ⏳ |
| 08 | Master Code Blueprints & FAANG L7 Interview Playbook | 3 | ⏳ |

### Folder 01 files

1. [01 · `PyObject` C structs, refcounting, cyclic GC & `__slots__` memory math](01-CPython-Runtime-Memory-Model-and-Concurrency-Physics/01-pyobject-c-structs-refcounting-cyclic-gc-and-slots-memory-math.md)
2. [02 · GIL internals vs free-threaded 3.14t/3.15t, mimalloc & QSBR](01-CPython-Runtime-Memory-Model-and-Concurrency-Physics/02-gil-internals-vs-free-threaded-python-314t-315t-mimalloc-and-qsbr.md)
3. [03 · Concurrency matrix: threading, multiprocessing, shared memory, asyncio/uvloop](01-CPython-Runtime-Memory-Model-and-Concurrency-Physics/03-concurrency-matrix-threading-multiprocessing-shared-memory-and-asyncio-uvloop.md)
4. [04 · Descriptors, metaclasses, specialization, generators & Pydantic v2](01-CPython-Runtime-Memory-Model-and-Concurrency-Physics/04-advanced-object-model-descriptors-metaclasses-generators-and-pydantic-v2-rust.md)

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
| Hardware | Intel i5-11260H (Tiger Lake, 6C/12T), 16 GB, Windows 11 | all timings |

## Verification method

1. Listings live in a scratch harness and run sequentially (`f01.sh`, one process at a time).
2. Markdown templates splice in each listing's bytes and its captured output, so the KB text *is* the executed code.
3. The **gate** extracts every listing back out of the KB markdown, checks it's byte-identical to the source, rebuilds and reruns all of them from the extracted copies, and diffs the outputs. Deterministic outputs must match exactly; measured ones must match once digits are masked. It also checks the section spine, the four parts of every Q&A chain, fences and CRLF.
4. Every cited URL is fetched once; relative links are resolved.

Folder 01 gate: **21 listings byte-identical, 22 build/run steps OK from the KB copies, 5 outputs identical, 17 differ only in measured numbers. 66/66 URLs OK.**

## What could not be executed here (and how it was covered)

- **Free-threaded CPython (3.14t/3.15t).** The PSF-signed `python-freethreaded` NuGet builds were downloaded and their Authenticode signatures verified, but this environment's safety policy refused to run a downloaded executable. Covered by compiling the real headers with `Py_GIL_DISABLED` (exact layouts), a C model of biased-refcount physics (`brc_physics.c`), and `ft_scaling_probe.py`, which prints a stated prediction for you to check by running it on `python3.14t`.
- **uvloop** (no Windows support) and the **Linux `fork`/`forkserver` start methods and `/dev/shm`**: explained from source and docs, and marked ⚠.

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
