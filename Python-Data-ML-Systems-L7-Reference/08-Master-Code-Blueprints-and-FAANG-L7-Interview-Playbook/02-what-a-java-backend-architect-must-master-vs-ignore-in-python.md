# 08.2 · What a Java Backend Architect Must Master vs. Ignore in Python

> **Folder 08 · Master Code Blueprints & FAANG L7 Interview Playbook**
> **Measured on:** CPython 3.14.5 (default GIL build), NumPy 2.5.4, Windows 11. The listing's output is deterministic.
> **Scope:** a prioritization for a Staff/Principal JVM and C++ engineer moving into Python data and ML systems. Each "master" item points to the folder where it's measured.

---

## 0. Orientation & the JVM/C++ Bridge

Python in data and ML is a **two-level system**: Python is the control plane, and C, C++, Rust and CUDA are the data plane. Almost every performance and correctness question a JVM architect faces in this stack comes down to which side of that line the work is on, and what it costs to cross it. Mastering Python here means mastering the boundary: object costs, the GIL, buffer sharing, vectorization, and how the frameworks schedule native work. The language trivia that consumes most Python tutorials matters far less.

| JVM / C++ habit | Python reality | Where measured |
|---|---|---|
| "objects are cheap; the JIT and GC handle it" | a boxed int is 32 B, an instance ~96 B; 10M ints ≈ 402 MB | 01.1 |
| "threads give parallelism" | one GIL in the default build; free-threaded 3.14t exists but its ecosystem is partial | 01.2 |
| "loops are fine; HotSpot optimizes them" | a per-element Python loop is 10–100× slower than a vectorized kernel | 02.2, 03.2 |
| "serialization at boundaries is normal" | Arrow buffers cross library boundaries with zero copies | 02.3, 08.1 |
| "a type error is a compile error" | annotations are not enforced at run time | §2 (row 9) |
| "Maven/Gradle builds everything" | binary wheels with ABI tags; CUDA builds per driver/toolkit | §1.3 |
| "the JVM is the platform" | CPython + native extensions; versions of both matter (3.14.5 reverted the 3.14.0 GC) | 01.1 |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 The master / learn-enough / ignore map

```text
 MASTER (you will be judged on these)
   CPython object model and memory: PyObject header, refcounting + cyclic GC, inline values, __slots__   01.1
   the GIL, free-threading (3.14t: biased refcounts, mimalloc, QSBR), threads vs processes vs asyncio  01.2–01.3
   NumPy: strides, views vs copies, broadcasting, ufunc dispatch, dtype promotion (NEP 50)            02.1–02.2
   Arrow: buffers, C Data Interface / PyCapsules, zero copy across Polars/DuckDB/pandas/torch          02.3, 08.1
   lazy engines: Polars pushdown and streaming, DuckDB, pandas 3 copy-on-write                         03
   the JVM↔Python bridge: PySpark/Beam workers, Arrow UDFs, Ray's object store                         04
   PyTorch: tensors/strides, dispatcher, autograd, torch.compile, GPU execution, AMP, allocator        06
   distributed training math (ring, ZeRO/FSDP, TP), quantization/LoRA/attention, serving/batching     07
   asyncio correctness: never block the loop; executors; cancellation; backpressure                   01.3, 07.3
 LEARN ENOUGH (read and review, rarely write)
   descriptors and metaclasses (frameworks use them; you debug through them)                          01.4
   Cython / Numba / C extensions (when a hot loop can't be vectorized)                                 02.2
   scikit-learn estimator API, GBDT libraries, ONNX export                                             05
   typing at scale (mypy/pyright), pydantic v2 / msgspec at boundaries                                 01.4
   packaging: pyproject.toml, wheels, ABI tags (cp314, abi3; abi3t is 3.15), uv lockfiles (⚠ not run)
 IGNORE (as an architect)
   micro-optimizing pure-Python loops (vectorize or move to native instead)
   __slots__ on every class (only where millions of instances exist)
   gevent/Twisted monkey-patching for new code (use asyncio)
   TorchScript and TF1-style static graphs (maintenance mode; use torch.compile / torch.export)
   hand-written CUDA C for standard ops (Inductor/Triton generate them; write Triton for novel kernels)
   conda-vs-pip debates (pick one lockfile-based workflow and standardize)
```

### 1.2 Tooling map

| Need | JVM tool | Python equivalent |
|---|---|---|
| Build + dependencies | Maven / Gradle | `pyproject.toml` + uv or pip-tools lockfiles (⚠ uv not run here) |
| Artifact | jar / fat jar | wheel (`.whl`); container image for CUDA stacks |
| Native interop | JNI / FFM API | C extensions, ctypes/cffi, nanobind/pybind11, PyO3 (Rust) |
| Unit tests | JUnit 5 | pytest (+ hypothesis for property tests) |
| Static analysis | Checkstyle, SpotBugs, Error Prone | ruff (lint + format), mypy / pyright |
| Microbenchmarks | JMH | `pyperf`, `timeit`, pytest-benchmark |
| Profiling | JFR, async-profiler | py-spy (sampling, ⚠ not run), `perf` with `-X perf`, cProfile, scalene |
| Memory | heap dumps, JFR allocation events | tracemalloc, memray (⚠ not run), `torch.cuda.memory._dump_snapshot` |
| Runtime flags | `-Xmx`, `-XX:` flags | `PYTHON*` env vars, `-X` options, `gc.freeze()`, `sys.setswitchinterval` |

### 1.3 Packaging is part of the architecture

```text
 a wheel's tags pin it: cp314-cp314-win_amd64 (CPython 3.14 ABI, Windows x64); abi3 = stable ABI across versions
 free-threaded builds need separate wheels (cp314t); 3.15 adds abi3t (PEP 803) for a free-threaded stable ABI
 GPU stacks: torch 2.14.1+cu130 bundles its CUDA runtime; the driver must be new enough (here driver 610.78)
 Triton on Windows needs a community build (triton-windows) and a C compiler for its launcher (06.3)
 lock everything (interpreter, wheels, CUDA build) per deployable; reproducibility is a lockfile + base image
```

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

Sixteen places where a correct Java instinct produces wrong Python, each executed:

```python
"""java_instinct_traps.py - sixteen places where a correct Java instinct produces wrong Python, each executed.

Every row prints what a Java engineer expects and what CPython 3.14 actually does. All results are deterministic.
"""
import dataclasses
import datetime

import numpy as np

rows = []


def check(name, java, got):
    rows.append((name, java, got))


# 1. default arguments are evaluated once, at def time
def add(item, acc=[]):
    acc.append(item)
    return acc


add(1)
check("mutable default argument", "acc is a new list per call", f"second call returns {add(2)}")

# 2. closures capture variables, not values (Java forces effectively-final captures)
fs = [lambda: i for i in range(3)]
check("closure in a loop", "[0, 1, 2]", str([f() for f in fs]))

# 3. identity vs equality (Java: Integer cache -128..127; CPython: -5..256)
a, b = int("1000"), int("1000")
c, d = int("100"), int("100")
check("`is` on ints", "== semantics, or cache-dependent like Integer", f"1000 is 1000: {a is b}; 100 is 100: {c is d}")

# 4. sequence repetition copies references
grid = [[0] * 3] * 3
grid[0][0] = 1
check("[[0]*3]*3 grid", "new int[3][3]: independent rows", f"{grid}")

# 5. integer arithmetic: no overflow in Python, silent wraparound in NumPy, floor semantics
big = 2**63 * 4
wrapped = np.array([2**62], dtype=np.int64) * 4
check("int overflow", "long wraps (or multiplyExact throws)", f"Python {big}; NumPy int64 array {wrapped.tolist()}")
check("-7 // 2 and -7 % 2", "-7/2 = -3, -7%2 = -1", f"{-7 // 2} and {-7 % 2} (floor division)")


# 6. equals/hashCode: an eq=True dataclass is unhashable unless frozen
@dataclasses.dataclass
class Point:
    x: int
    y: int


@dataclasses.dataclass(frozen=True, slots=True)
class FrozenPoint:
    x: int
    y: int


try:
    {Point(1, 2)}
    msg = "hashable"
except TypeError as e:
    msg = f"TypeError: {e}"
check("mutable dataclass in a set", "works if equals/hashCode are overridden", msg)
check("frozen, slots dataclass (record)", "record Point(int x, int y)", f"hashable: {hash(FrozenPoint(1, 2)) == hash(FrozenPoint(1, 2))}")


# 7. annotations are not enforced at run time
def double(x: int) -> int:
    return x * 2


check("type hints", "compile error for double(\"ab\")", f"double('ab') = {double('ab')!r}")

# 8. a generator is single-pass and fails silently on reuse (Java Streams throw IllegalStateException)
g = (n for n in range(5))
check("reusing a generator", "IllegalStateException on 2nd use", f"sum twice: {sum(g)}, then {sum(g)}")

# 9. truthiness of arrays
try:
    if np.array([1, 2]):
        pass
    msg = "ok"
except ValueError as e:
    msg = f"ValueError: {str(e)[:52]}..."
check("if <numpy array>:", "compile error (not a boolean)", msg)

# 10. a bare except catches interpreter exits
try:
    try:
        raise SystemExit(3)
    except:                                              # noqa: E722 - the trap itself
        caught = "SystemExit swallowed"
except SystemExit:
    caught = "propagated"
check("bare `except:`", "catch (Exception e) doesn't catch Error", caught)

# 11. naive vs aware datetimes (LocalDateTime vs Instant), and they don't compare
naive, aware = datetime.datetime(2026, 1, 1), datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
try:
    naive < aware
    msg = "comparable"
except TypeError as e:
    msg = f"TypeError: {e}"
check("naive vs aware datetime", "compile error mixing LocalDateTime/Instant", msg)

# 12. dicts keep insertion order; equality ignores order
d1, d2 = {"b": 1, "a": 2}, {"a": 2, "b": 1}
check("dict order", "HashMap: unspecified order", f"list(d1) = {list(d1)}; d1 == d2: {d1 == d2}")

# 13. chained comparison
check("1 < 3 > 2", "compile error (boolean > int)", f"{1 < 3 > 2} (means 1 < 3 and 3 > 2)")

# 14. summation: built-in sum() of floats is compensated since 3.12; a hand-written loop is not
vals = [0.1] * 10
acc = 0.0
for v in vals:
    acc += v
check("summing ten 0.1s", "a for-loop: 0.9999999999999999",
      f"loop {acc!r}; sum() {sum(vals)!r} (compensated); np.sum {float(np.sum(vals))!r} (pairwise)")

w = max(len(r[0]) for r in rows)
for i, (name, java, got) in enumerate(rows, 1):
    print(f"{i:2d}. {name:{w}}  Java instinct: {java}")
    print(f"    {'':{w}}  CPython 3.14:  {got}")
assert len(rows) == 16 and acc != sum(vals)
print("ALL ASSERTIONS PASSED")
```

Output (deterministic, verified):

```text
 1. mutable default argument          Java instinct: acc is a new list per call
                                      CPython 3.14:  second call returns [1, 2]
 2. closure in a loop                 Java instinct: [0, 1, 2]
                                      CPython 3.14:  [2, 2, 2]
 3. `is` on ints                      Java instinct: == semantics, or cache-dependent like Integer
                                      CPython 3.14:  1000 is 1000: False; 100 is 100: True
 4. [[0]*3]*3 grid                    Java instinct: new int[3][3]: independent rows
                                      CPython 3.14:  [[1, 0, 0], [1, 0, 0], [1, 0, 0]]
 5. int overflow                      Java instinct: long wraps (or multiplyExact throws)
                                      CPython 3.14:  Python 36893488147419103232; NumPy int64 array [0]
 6. -7 // 2 and -7 % 2                Java instinct: -7/2 = -3, -7%2 = -1
                                      CPython 3.14:  -4 and 1 (floor division)
 7. mutable dataclass in a set        Java instinct: works if equals/hashCode are overridden
                                      CPython 3.14:  TypeError: cannot use 'Point' as a set element (unhashable type: 'Point')
 8. frozen, slots dataclass (record)  Java instinct: record Point(int x, int y)
                                      CPython 3.14:  hashable: True
 9. type hints                        Java instinct: compile error for double("ab")
                                      CPython 3.14:  double('ab') = 'abab'
10. reusing a generator               Java instinct: IllegalStateException on 2nd use
                                      CPython 3.14:  sum twice: 10, then 0
11. if <numpy array>:                 Java instinct: compile error (not a boolean)
                                      CPython 3.14:  ValueError: The truth value of an array with more than one eleme...
12. bare `except:`                    Java instinct: catch (Exception e) doesn't catch Error
                                      CPython 3.14:  SystemExit swallowed
13. naive vs aware datetime           Java instinct: compile error mixing LocalDateTime/Instant
                                      CPython 3.14:  TypeError: can't compare offset-naive and offset-aware datetimes
14. dict order                        Java instinct: HashMap: unspecified order
                                      CPython 3.14:  list(d1) = ['b', 'a']; d1 == d2: True
15. 1 < 3 > 2                         Java instinct: compile error (boolean > int)
                                      CPython 3.14:  True (means 1 < 3 and 3 > 2)
16. summing ten 0.1s                  Java instinct: a for-loop: 0.9999999999999999
                                      CPython 3.14:  loop 0.9999999999999999; sum() 1.0 (compensated); np.sum 1.0 (pairwise)
ALL ASSERTIONS PASSED
```

* **Rows 1–4** are the classic production bugs. Use `None` defaults, bind loop variables as default args or with `functools.partial`, compare with `==` (never `is`, except for `None`), and use list comprehensions for 2-D structures.
* **Rows 5–6**: Python ints never overflow, but **NumPy int64 arrays wrap silently** (`2**62 * 4 → 0`). Floor division differs from Java's truncation for negatives. Data pipelines mixing the two need explicit dtype checks.
* **Rows 7–9**: `frozen=True, slots=True` dataclasses are the record analogue. Annotations are documentation until a checker (mypy/pyright) or validator (pydantic/msgspec) enforces them.
* **Rows 10–13**: silent single-pass generators, ambiguous array truthiness, a bare `except:` that swallows `SystemExit`, and naive vs aware datetimes are the four most expensive "it ran but did the wrong thing" bugs in data code.
* **Row 16**: since 3.12, built-in `sum()` of floats is compensated (1.0), while a hand-written loop gives 0.9999999999999999, so two "equivalent" implementations of a metric can disagree in the last bit.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Adding threads makes the service slower | CPU one core; throughput flat | GIL on Python bytecode | Processes, vectorization, or native code that releases the GIL | Know where the work runs (01.2) |
| F2 🔥 | Shared state "leaks" between requests | Data from a previous call appears | Mutable default argument or module-level mutable | `None` defaults; per-request objects | ruff rule B006 (mutable defaults) |
| F3 | Callbacks all use the last loop value | Closures in loops | Late binding | Default-arg binding or `partial` | ruff B023 |
| F4 🔥 | Silent wrong aggregates | int64 sums overflow, no error | NumPy wraparound | Wider dtypes, `np.add.reduce(..., dtype=object)` for audits, range checks | Property tests with extreme values |
| F5 | A pipeline step produces empty output | Generator consumed earlier | Single-pass iterators | Materialize (`list`) or re-create | Type hints `Iterator` vs `Iterable`; tests |
| F6 | `TypeError: can't compare offset-naive and offset-aware datetimes` | Mixed timestamp sources | Naive datetimes | UTC-aware everywhere (`tz=timezone.utc`) | Lint `datetime.now()` without tz |
| F7 | Service ignores SIGTERM / won't stop | Bare `except:` around loops | Catches `SystemExit`/`KeyboardInterrupt` | `except Exception:` | ruff E722 |
| F8 🔥 | Import works locally, fails in production | `undefined symbol` / DLL load failed | Wheel/ABI/CUDA mismatch | Pin interpreter + wheels + CUDA build in one lockfile/image | Build images from the lockfile in CI |
| F9 | Type-annotated API accepts garbage | Wrong types at run time | Annotations unenforced | Validate at boundaries (pydantic v2, msgspec) | mypy/pyright strict in CI |
| F10 | Worker processes re-run startup code | Logs printed N+1 times | `spawn` re-imports `__main__` | `if __name__ == "__main__":` | Side-effect-free modules (08.1) |

**Debugging toolkit.** `python -X dev` (extra runtime checks, ResourceWarnings); `faulthandler.dump_traceback_later`; `tracemalloc` snapshots; `py-spy dump --pid` for stuck processes (⚠ not run); `python -X importtime` for slow imports; `sys.getrefcount` / `gc.get_referrers` for leaks; `PYTHONASYNCIODEBUG=1` for blocked loops.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Our org is Java-first. How do we introduce Python for ML without creating a mess?"</b></summary>

**Initial Prompt.** A 300-engineer JVM organization starts an ML platform.

**L5 Answer.** "Let the data scientists use whatever they want in notebooks."

**Why L5 Crashes at Scale.** Notebook code becomes production by accident: unpinned dependencies, pandas row loops in the hot path, JSON between services, no types or tests. The JVM teams then can't operate it, and the ML teams can't integrate with JVM data.

**L7 Principal Defense.** Define boundaries and contracts. Data crosses as **Arrow/Parquet** with versioned schemas (08.1 Q7), and services talk gRPC or Arrow Flight, never pickled objects. Ownership splits along the boundary: JVM teams own streaming and feature pipelines, where Spark/Flink are strongest; Python owns training and model serving with a batching core (07.3). Standardize tooling: one lockfile workflow, ruff + mypy/pyright in CI, pytest, container images that pin interpreter + wheels + CUDA build. Write the performance rules down (vectorize, no per-row Python in pipelines, Arrow UDFs not pickled ones: ~3–4× cheaper per row measured in 04.1). Review Python code for these, the way Java code is reviewed for allocation in hot paths.

</details>

<details><summary><b>Q2 · "Should we rewrite our Java feature pipeline in Python?"</b></summary>

**Initial Prompt.** The ML team wants features computed in the same language as training.

**L5 Answer.** "Yes. One language avoids training/serving skew."

**Why L5 Crashes at Scale.** It trades a mature, fast streaming stack for per-row Python. Measured in Folder 04: a JVM expression costs ~5 ns/row against ~90–400 ns/row for Python UDFs, 18–80× more CPU at the same event rate (08.3: 1M events/s needs ~0.01 cores in the JVM vs ~0.38 pickled). Skew comes from **two implementations of a feature**, not from two languages.

**L7 Principal Defense.** Keep feature computation in one place, the JVM streaming/batch pipeline, and make Python a consumer of its Arrow/Parquet outputs for training and of a feature store for serving. Skew is prevented by a single definition: the same compiled logic produces offline and online values, verified by parity tests on sampled keys. Where Python logic is unavoidable inside Spark, use Arrow UDFs or `mapInArrow`, never pickled row UDFs, and keep it vectorized. Rewrite only if the JVM pipeline is the bottleneck for iteration speed, and measure first.

</details>

<details><summary><b>Q3 · "Which Python internals must a Staff engineer actually know?"</b></summary>

**Initial Prompt.** Prioritize learning for a strong Java engineer joining an ML platform team.

**L5 Answer.** "Decorators, metaclasses, and generators. The advanced language features."

**Why L5 Crashes at Scale.** Those are language features, not system behaviour. Knowing metaclasses won't explain a 4 GB RAM blow-up, a GIL-bound service or a GPU at 30 % utilization, which are what Staff engineers get paged for.

**L7 Principal Defense.** Learn the cost model, in this order. (1) Object memory: 32 B ints, ~96 B instances, why 10M Python ints cost ~402 MB (01.1). (2) The GIL and its exits: native code that releases it, processes, free-threading's status (01.2). (3) Buffers and views: NumPy strides, Arrow, zero copy across libraries (02). (4) Vectorized and lazy engines: Polars/DuckDB/pandas 3 CoW (03). (5) The framework runtime you operate: PyTorch's dispatcher, autograd, compile and allocator (06), or Spark's Python workers (04). Descriptors and metaclasses come after, as debugging knowledge. The §1.1 map is the syllabus.

</details>

<details><summary><b>Q4 · "Type safety in a large Python codebase?"</b></summary>

**Initial Prompt.** Java engineers worry about refactoring 500k lines of Python.

**L5 Answer.** "Add type hints everywhere; Python will check them."

**Why L5 Crashes at Scale.** Python ignores annotations at run time (`double("ab")` returned `'abab'`, row 9). Type hints without a checker are comments, and checkers don't validate external data.

**L7 Principal Defense.** Use three layers. A static checker (mypy or pyright) in strict mode for owned packages in CI, gradually expanding coverage, with `Protocol`s for interfaces. Runtime validation at trust boundaries: request bodies, messages and config via pydantic v2 or msgspec (01.4 measured their costs), with fail-fast errors. And tests: pytest + hypothesis for invariants. Treat `Any` as a reviewed exception. That gives roughly Java-level refactoring confidence where it matters, without paying validation costs in inner loops.

</details>

<details><summary><b>Q5 · "Package a CUDA Python service reproducibly."</b></summary>

**Initial Prompt.** "Works on my machine" failures every release: DLL load errors, CUDA mismatches.

**L5 Answer.** "Use `pip install -r requirements.txt` with versions pinned."

**Why L5 Crashes at Scale.** Version pins without hashes and platform tags don't pin the build. CUDA wheels exist per CUDA toolkit (`+cu130`), need a minimum driver, and transitive dependencies (NumPy ABI, Triton, compilers) drift.

**L7 Principal Defense.** Lock the full resolution with hashes per platform (uv/pip-tools lockfiles) and choose the CUDA variant explicitly from the right index. Build one container image per deployable from the lockfile in CI, with the interpreter version pinned (patch versions matter: 3.14.5 reverted the GC change of 3.14.0–3.14.4, 01.1). Record the driver requirement and check `torch.version.cuda` and `torch.cuda.is_available()` at startup (fail fast). Run a GPU smoke test (a tiny `torch.compile` model) in CI on the target driver. For Windows dev boxes, document the extra pieces this KB needed (triton-windows, a C compiler for Triton) as unsupported for production.

</details>

<details><summary><b>Q6 · "Should we adopt free-threaded Python now?"</b></summary>

**Initial Prompt.** 3.14t removes the GIL. Does that end the multiprocessing pain?

**L5 Answer.** "Yes. Switch the interpreter and threads scale."

**Why L5 Crashes at Scale.** Free-threading is a different ABI: every C extension needs a `cp314t` build declaring `Py_mod_gil`, and importing one that doesn't **re-enables the GIL for the whole process** (01.2). Single-thread performance carries overhead from biased refcounting and atomics, and code that relied on the GIL for safety races.

**L7 Principal Defense.** Treat it as a platform migration with a gate. Inventory native dependencies for free-threaded wheels, run the test suite with `PYTHON_GIL=0` and thread-stress tests, and benchmark single-thread and scaling on your real workload. ⚠ This KB couldn't execute 3.14t (running a downloaded interpreter was blocked), so its claims come from compiled headers and a model (01.2). Adopt first where the win is largest and dependencies are ready: CPU-bound Python in thread pools, loaders doing Python-level transforms (08.1 §1.4). Plan around 3.15's `abi3t` for stable-ABI extensions. Meanwhile, processes and native code that releases the GIL remain the production answer.

</details>

<details><summary><b>Q7 · "What replaces JFR and async-profiler for production Python?"</b></summary>

**Initial Prompt.** A Python service has p99 spikes; the team only knows JVM tooling.

**L5 Answer.** "Add logging with timestamps around every function."

**Why L5 Crashes at Scale.** Manual logging perturbs timing, misses native frames (NumPy, torch, Arrow) and GIL waits, and can't attribute time across threads.

**L7 Principal Defense.** Use sampling profilers that see both Python and native stacks: py-spy (`record`, `dump` for hangs, no code changes; ⚠ not run here), `perf` with `python -X perf` for Python frames in Linux perf, and scalene for CPU/memory split. For memory: tracemalloc snapshots diffed over time, memray for native allocations, `gc.get_stats()` and `gc.freeze()` for GC pauses (01.1). For async: `PYTHONASYNCIODEBUG` and a loop-lag metric (07.3). For GPU: `torch.profiler` traces and the CUDA memory snapshot (06.4). Production should continuously export loop lag, GC pause times, RSS/USS per process and batch sizes, the Python equivalents of JFR's always-on events.

</details>

<details><summary><b>Q8 · "Can Python be in the hot path of a 50k QPS service?"</b></summary>

**Initial Prompt.** A ranking service must score 50k requests/s with p99 < 20 ms.

**L5 Answer.** "No. Rewrite in Java or Go."

**Why L5 Crashes at Scale.** The blanket answer ignores where the cost is. A Python process handles ~1–2.5k HTTP requests/s (07.3 measured), but the model math in batched native kernels handles ~150k items/s per GPU call path (07.3: 6.4 µs per request at batch 128). A rewrite of the model runtime gains little; the per-request Python overhead is the actual limit.

**L7 Principal Defense.** Separate the request plane from the compute plane. Use a non-Python or C++ front end (Envoy, a Java/Go gateway, or Triton's C++ server) for parsing, auth and fan-in, and batch requests into it. Run Python where it orchestrates batched native work (one GPU-owning batcher per GPU), or export the model (ONNX/TensorRT, `torch.export` + AOTInductor) so no Python runs per request. Size it with napkin math: 50k req/s ÷ ~2k req/s per Python process ≈ 25 processes if Python stays per request, versus a handful of GPU batchers behind a C++ front end. Verify with open-loop load tests against the p99 target (07.3 Q9).

</details>

---

## 5. Invariants Checklist

- [ ] Python is the control plane; native code is the data plane. Optimize the boundary, not the language.
- [ ] Learn the cost model first: object bytes, the GIL, buffers and views, vectorized engines, the framework runtime.
- [ ] `None` defaults, bound closures, `==` not `is`, list comprehensions for 2-D, UTC-aware datetimes, `except Exception`.
- [ ] NumPy integer arrays wrap silently, and Python ints never overflow. Check dtypes at boundaries.
- [ ] Annotations aren't enforced. Use static checkers in CI and validators at trust boundaries.
- [ ] Lock interpreter + wheels + CUDA build together. Patch versions change runtime behaviour.
- [ ] Free-threading is a platform migration with an ABI, not a flag.

---

## 6. References

- Python docs: data model — https://docs.python.org/3/reference/datamodel.html
- Python docs: `dataclasses` (frozen, slots) — https://docs.python.org/3/library/dataclasses.html
- Python docs: `sum()` (compensated float summation since 3.12) — https://docs.python.org/3/library/functions.html#sum
- Python docs: free-threading HOWTO — https://docs.python.org/3/howto/free-threading-python.html
- PEP 703 — Making the Global Interpreter Lock Optional in CPython — https://peps.python.org/pep-0703/
- PEP 803 — Stable ABI for free-threaded builds (abi3t) — https://peps.python.org/pep-0803/
- Python Packaging User Guide: platform compatibility tags — https://packaging.python.org/en/latest/specifications/platform-compatibility-tags/
- NumPy docs: overflow errors in integer arrays — https://numpy.org/doc/stable/user/basics.types.html#overflow-errors
- ruff rules (B006, B023, E722) — https://docs.astral.sh/ruff/rules/
- mypy documentation — https://mypy.readthedocs.io/en/stable/
- PyTorch docs: installing CUDA builds — https://pytorch.org/get-started/locally/
