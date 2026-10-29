# 04.2 · Apache Beam Python SDK: Runner v2 Portability, DoFn Lifecycle, Batched DoFns & RunInference

> **Folder 04 · Distributed Data Engineering: PySpark, Beam, Ray & Lakehouse**
> **Measured on:** Apache Beam 2.77.0 Python SDK with its portable **FnApiRunner** (in-process and 2 SDK-worker subprocesses over gRPC), CPython 3.14.5, NumPy 2.4.6 (Beam's pinned stack), i5-11260H, Windows 11.
> **Design sources:** Beam portability docs (Runner API, Fn API), `apache_beam/runners/portability/` source, and the Batched DoFn and RunInference guides.
> ⚠ **Two things found while building this file.** (1) Beam 2.77's `DirectRunner` silently delegated to **PrismRunner**, a Go runner binary that Beam downloads at run time into `~/.apache_beam/cache`. That happened once here; I deleted the cache and every listing pins the pure-Python `FnApiRunner`, and the harness fails if the cache reappears. (2) On Windows, multi-process mode failed because Beam launches workers with `shell=True` and an unquoted `sys.executable`, which breaks on `C:\Program Files\...`. Running Python via its 8.3 short path works around it.

---

## 0. Orientation & the JVM/C++ Bridge

You already know Beam's model (PCollections, windows, triggers, Dataflow) from the Unified Dataflow/Beam/Flink KB. This file is about **what the Python SDK physically does**. A Beam pipeline is a portable protobuf graph (the Runner API). A runner (Dataflow Runner v2, Flink, Spark, Prism, the Python FnApiRunner) executes it by sending *bundles* of work to **SDK harness** processes over the **Fn API**. With a Python SDK, every element of a Python transform crosses into a Python process, so Python per-element costs, fusion and batching dominate throughput, exactly as the UDF hop did in PySpark (04.1).

| Concept | Beam Python (portable) | Java SDK on Dataflow | PySpark analogue |
|---|---|---|---|
| Pipeline representation | Runner API protobuf | same | logical plan |
| Execution unit | bundle of elements → SDK harness | bundle in the same JVM | task → Python worker |
| Runner ↔ SDK protocol | Fn API: gRPC control, data, state, logging planes | in-process | local socket (04.1) |
| Fusion | runner fuses ParDos into stages; GBK/Reshuffle breaks fusion | same | whole-stage codegen |
| Batching | `process_batch` / `yields_batches`, `BatchElements` | n/a | `pandas_udf` |
| Model scoring | `RunInference` + `ModelHandler` | — | `mapInPandas` + broadcast |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 Runner v2 and the Fn API

```text
 Dataflow worker VM (Runner v2)                          SDK harness container(s) (Python)
 +----------------------------+   gRPC Control: ProcessBundleRequest(stage, bundle id) +------------------+
 | Runner harness (C++)       | ------------------------------------------------------>| sdk_worker       |
 | Streaming Engine/Shuffle   |   gRPC Data: element streams, encoded with coders      |  bundle processor|
 | windows, timers, GBK state |<======================================================>|  fused DoFn chain|
 | (in Windmill/Shuffle svc)  |   gRPC State: side inputs, user state, bag/value      |                  |
 +----------------------------+   gRPC Logging / Progress / Monitoring                 +------------------+
 The Python FnApiRunner reproduces this locally:
   in_memory        : runner and SDK harness in one process (direct calls, no gRPC)
   multi_processing : N SDK worker subprocesses ("Data channel established" over loopback gRPC)
```

The runner fuses consecutive ParDos into one **stage**. Inside a stage, elements flow between DoFns as Python objects without encoding. Between stages (after a GroupByKey, Reshuffle, side input or CoGroupByKey) they're encoded with coders and cross the data plane. Measured: a Reshuffle cost **~19–33 µs per element**, more than ten times the in-stage per-element DoFn cost (~3 µs).

### 1.2 The DoFn lifecycle

```text
 per DoFn INSTANCE (deserialized once per SDK worker thread, reused across bundles):
   setup()                -> open clients, load models: amortized over many bundles
   for each bundle:
     start_bundle()       -> per-bundle buffers
     process(element) ... -> per element (or process_batch(batch) per batch)
     finish_bundle()      -> flush buffers; emit WindowedValues if needed
   teardown()             -> BEST EFFORT: not guaranteed (worker may be killed)
```

Measured counts (§2.1): in-process the runner created 2 DoFn instances (2 bundles); in multi-process mode each of the 2 worker processes ran setup → bundle → teardown once. Put expensive initialization in `setup`, buffer or flush in `start_bundle`/`finish_bundle`, and **never rely on `teardown`** for correctness (use `finish_bundle` for flushing).

### 1.3 Batched DoFns (Beam ≥ 2.42)

`process_batch(self, batch: np.ndarray)` lets a DoFn receive a NumPy, pandas or pyarrow batch. Beam's batch converters build batches from elements and explode them back where a downstream transform needs elements. **The win only materializes when the producer is batched too** (`@beam.DoFn.yields_batches`) and the consumer stays batched. A batched DoFn fed by a per-element `FlatMap` paid for exploding *and* re-batching, and was no faster during development of §2.1. End-to-end batching (or simply ndarrays as elements) was ~4.3× faster.

### 1.4 RunInference

```text
 PCollection[example] -> BatchElements(min, max batch size) -> RunInference(ModelHandler)
   ModelHandler.load_model()       once per process (optionally shared across processes)
   ModelHandler.run_inference(batch, model) -> one framework call per batch (matmul / ONNX / torch)
   -> PredictionResult(example, inference)
```

`batch_elements_kwargs()` bounds batch sizes, and the end of a bundle flushes a short batch. With `share_model_across_processes`/`large_model` (⚠ not exercised here), one model copy serves all SDK processes on a VM, which matters when a 2 GB model meets a 16-process worker.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Lifecycle, batching and the cost of crossing the data plane

```python
"""beam_dofn_batching.py - Beam's DoFn lifecycle and the per-element vs batched cost, in-process and over the Fn API.

Runs the Python portable runner (FnApiRunner) in two modes: in_memory (SDK harness in this process) and
multi_processing (2 SDK worker subprocesses talking gRPC over loopback: the Fn API control + data planes, the
protocol Dataflow Runner v2 uses between its runner harness and the Python SDK container).
A: which lifecycle methods run how often, per worker process (logged to files: setup/teardown run outside bundles).
B: 300k values three ways: exploded to elements + per-element process(); Beam batched DoFns kept batched end to
   end (yields_batches -> process_batch -> per-batch partial sums); and plain ndarrays as elements.
C: what a Reshuffle (GroupByKey on random keys, i.e. a data-plane crossing) costs per element.
"""
import collections
import logging
import os
import tempfile
import time
from typing import Iterator

import apache_beam as beam
import numpy as np
from apache_beam.metrics import Metrics
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.runners.portability.fn_api_runner import FnApiRunner

logging.getLogger().setLevel(logging.ERROR)
SEEDS, PER_SEED = 300, 1_000


class PerElement(beam.DoFn):
    def __init__(self, logdir=None):
        self.logdir = logdir

    def _log(self, event):
        if self.logdir:
            with open(os.path.join(self.logdir, f"{os.getpid()}.log"), "a") as f:
                f.write(event + "\n")

    def setup(self):
        self._log("setup")                               # once per DoFn instance: load models/clients here

    def start_bundle(self):
        self._log("start_bundle")

    def process(self, x):
        yield x * 1.18 + 2                               # one Python call + element handling per element

    def finish_bundle(self):
        self._log("finish_bundle")

    def teardown(self):
        self._log("teardown")                            # best effort: not guaranteed to run


class Batched(beam.DoFn):
    def process_batch(self, batch: np.ndarray) -> Iterator[np.ndarray]:
        Metrics.distribution("life", "batch_size").update(len(batch))
        yield batch * 1.18 + 2                           # one NumPy call per batch

    def infer_output_type(self, input_type):
        return np.float64


class BatchProducer(beam.DoFn):
    @beam.DoFn.yields_batches
    def process(self, i) -> Iterator[np.ndarray]:
        yield expand(i)                                  # emits a batch; elements never materialize

    def infer_output_type(self, input_type):
        return np.float64


class BatchSum(beam.DoFn):
    def process_batch(self, batch: np.ndarray) -> Iterator[np.ndarray]:
        yield np.array([batch.sum()])                    # one partial sum per batch

    def infer_output_type(self, input_type):
        return np.float64


def expand(i):
    return np.arange(i * PER_SEED, (i + 1) * PER_SEED, dtype=np.float64)


def run_variant(mode, variant):
    opts = PipelineOptions([f"--direct_running_mode={mode}", "--direct_num_workers=2"])
    p = beam.Pipeline(runner=FnApiRunner(), options=opts)
    seeds = p | beam.Create(list(range(SEEDS)))
    if variant == "exploded":
        out = (seeds | beam.FlatMap(expand).with_output_types(np.float64)
               | beam.ParDo(PerElement()).with_output_types(np.float64))
    elif variant == "batched":
        out = (seeds | beam.ParDo(BatchProducer()) | beam.ParDo(Batched()) | beam.ParDo(BatchSum()))
    else:
        out = (seeds | "Expand" >> beam.Map(expand) | "Scale" >> beam.Map(lambda a: a * 1.18 + 2)
               | "PartialSum" >> beam.Map(lambda a: float(a.sum())))
    _ = out | beam.CombineGlobally(sum)
    t0 = time.perf_counter()
    result = p.run()
    result.wait_until_finish()
    return time.perf_counter() - t0


def run(mode, dofn, reshuffle=False, seeds=SEEDS):
    opts = PipelineOptions([f"--direct_running_mode={mode}", "--direct_num_workers=2"])
    p = beam.Pipeline(runner=FnApiRunner(), options=opts)
    pc = (p | beam.Create(list(range(seeds)))
          | beam.FlatMap(expand).with_output_types(np.float64))   # elements are born inside the worker
    if reshuffle:
        pc = pc | beam.Reshuffle()
    _ = pc | beam.ParDo(dofn).with_output_types(np.float64) | beam.CombineGlobally(sum)
    t0 = time.perf_counter()
    result = p.run()
    result.wait_until_finish()
    dt = time.perf_counter() - t0
    dists = [d.committed for d in result.metrics().query()["distributions"] if d.key.metric.name == "batch_size"]
    return dt, dists


if __name__ == "__main__":
    n = SEEDS * PER_SEED
    print(f"apache_beam {beam.__version__}; FnApiRunner; {n:,} elements (x * 1.18 + 2)")
    print("== A. lifecycle calls per SDK worker process (per-element DoFn)")
    for mode in ("in_memory", "multi_processing"):
        logdir = tempfile.mkdtemp()
        run(mode, PerElement(logdir))
        files = sorted(os.listdir(logdir))
        per = [collections.Counter(open(os.path.join(logdir, f)).read().split()) for f in files]
        summary = "; ".join(", ".join(f"{k}={c[k]}" for k in ("setup", "start_bundle", "finish_bundle", "teardown"))
                            for c in per)
        print(f"  {mode:16} {len(files)} process(es): {summary}")
        for f in files:
            os.remove(os.path.join(logdir, f))
        os.rmdir(logdir)

    print("== B. the same 300k values: element-at-a-time vs batch-at-a-time")
    print(f"  {'mode':16} {'variant':44} {'time':>7} {'us/value':>9}")
    res = {}
    for mode in ("in_memory", "multi_processing"):
        for variant, label in (("exploded", "FlatMap to elements + per-element process()"),
                               ("batched", "yields_batches -> process_batch -> BatchSum"),
                               ("arrays", "ndarray per element (manual batching)")):
            dt = run_variant(mode, variant)
            res[(mode, variant)] = dt
            print(f"  {mode:16} {label:44} {dt:6.2f}s {dt / n * 1e6:9.2f}")
        print(f"  {mode:16} batched DoFns {res[(mode, 'exploded')] / res[(mode, 'batched')]:.1f}x, arrays "
              f"{res[(mode, 'exploded')] / res[(mode, 'arrays')]:.1f}x faster than exploded")

    print("== C. adding a Reshuffle (GroupByKey on random keys) in front of the DoFn, 50k elements")
    for mode in ("in_memory", "multi_processing"):
        dt0, _ = run(mode, Batched(), reshuffle=False, seeds=50)
        dt1, _ = run(mode, Batched(), reshuffle=True, seeds=50)
        print(f"  {mode:16} without {dt0:5.2f}s  with Reshuffle {dt1:5.2f}s  -> {(dt1 - dt0) / 50_000 * 1e6:6.1f} us/elem "
              f"for the shuffle")
    assert res[("in_memory", "batched")] < res[("in_memory", "exploded")]
    print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
apache_beam 2.77.0; FnApiRunner; 300,000 elements (x * 1.18 + 2)
== A. lifecycle calls per SDK worker process (per-element DoFn)
  in_memory        1 process(es): setup=2, start_bundle=2, finish_bundle=2, teardown=2
  multi_processing 2 process(es): setup=1, start_bundle=1, finish_bundle=1, teardown=1; setup=1, start_bundle=1, finish_bundle=1, teardown=1
== B. the same 300k values: element-at-a-time vs batch-at-a-time
  mode             variant                                         time  us/value
  in_memory        FlatMap to elements + per-element process()    0.86s      2.88
  in_memory        yields_batches -> process_batch -> BatchSum    0.20s      0.67
  in_memory        ndarray per element (manual batching)          0.20s      0.66
  in_memory        batched DoFns 4.3x, arrays 4.4x faster than exploded
  multi_processing FlatMap to elements + per-element process()    2.83s      9.43
  multi_processing yields_batches -> process_batch -> BatchSum    2.49s      8.30
  multi_processing ndarray per element (manual batching)          2.49s      8.30
  multi_processing batched DoFns 1.1x, arrays 1.1x faster than exploded
== C. adding a Reshuffle (GroupByKey on random keys) in front of the DoFn, 50k elements
  in_memory        without  0.31s  with Reshuffle  1.97s  ->   33.1 us/elem for the shuffle
  multi_processing without  2.54s  with Reshuffle  3.51s  ->   19.3 us/elem for the shuffle
ALL ASSERTIONS PASSED
```

* **A:** lifecycle calls per worker process match §1.2. `setup` runs per DoFn instance, not per element.
* **B:** in-process, exploding 300 k values into elements costs ~2.9 µs per value. Keeping them batched (Beam batched DoFns, or ndarrays as elements) costs ~0.66 µs, **~4.3× faster**. In multi-process mode ~2.3 s of SDK-worker start-up dominates this small input, so the batch gain is hidden (1.1×). At production volumes the per-element term dominates again.
* **C:** a Reshuffle (GroupByKey on random keys) adds ~19–33 µs **per element**. Avoid unnecessary fusion breaks, and don't Reshuffle 1 B tiny elements: batch first, or reshuffle keys rather than rows.

### 2.2 Scoring a model: load-per-element vs `setup` vs RunInference

```python
"""beam_runinference.py - model scoring in Beam: load-per-element vs DoFn.setup vs RunInference (batched).

A toy linear model (64 features) with a simulated 50 ms load stands in for a real model. RunInference with a
custom ModelHandler loads the model once per process and scores BatchElements-sized batches in one matmul.
Load calls and batch sizes are logged to files (they happen in the SDK harness, outside the driver).
"""
import collections
import logging
import os
import tempfile
import time

import apache_beam as beam
import numpy as np
from apache_beam.ml.inference.base import ModelHandler, PredictionResult, RunInference
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.runners.portability.fn_api_runner import FnApiRunner

logging.getLogger().setLevel(logging.ERROR)
N, D = 4_000, 64
LOG = tempfile.mkdtemp()


def log(event):
    with open(os.path.join(LOG, f"{os.getpid()}.log"), "a") as f:
        f.write(event + "\n")


def load_weights():
    time.sleep(0.05)                                     # stands in for deserializing a real model
    log("load")
    return np.linspace(-1, 1, D)


class LinearHandler(ModelHandler):
    def load_model(self):
        return load_weights()

    def run_inference(self, batch, model, inference_args=None):
        log(f"batch {len(batch)}")
        scores = np.stack(batch) @ model                 # one matmul per batch
        return [PredictionResult(x, float(s)) for x, s in zip(batch, scores)]

    def batch_elements_kwargs(self):
        return {"min_batch_size": 64, "max_batch_size": 512}


class SetupScorer(beam.DoFn):
    def setup(self):
        self.w = load_weights()                          # once per DoFn instance

    def process(self, x):
        yield float(x @ self.w)                          # one tiny matmul per element


def naive_score(x):
    return float(x @ load_weights())                     # anti-pattern: load inside the per-element function


def run(kind, n):
    p = beam.Pipeline(runner=FnApiRunner(), options=PipelineOptions(["--direct_running_mode=in_memory"]))
    xs = p | beam.Create([np.full(D, i / n) for i in range(n)])
    if kind == "naive":
        scores = xs | beam.Map(naive_score)
    elif kind == "setup":
        scores = xs | beam.ParDo(SetupScorer())
    else:
        scores = xs | RunInference(LinearHandler()) | beam.Map(lambda r: r.inference)
    _ = scores | beam.CombineGlobally(sum) | beam.Map(lambda s: log(f"total {s:.6f}"))
    t0 = time.perf_counter()
    p.run().wait_until_finish()
    return time.perf_counter() - t0


def read_logs():
    c, batches, totals = collections.Counter(), [], []
    for f in os.listdir(LOG):
        for line in open(os.path.join(LOG, f)):
            kind, _, rest = line.strip().partition(" ")
            c[kind] += 1
            if kind == "batch":
                batches.append(int(rest))
            if kind == "total":
                totals.append(float(rest))
        os.remove(os.path.join(LOG, f))
    return c, batches, totals


if __name__ == "__main__":
    print(f"apache_beam {beam.__version__}; linear model with {D} features, simulated 50 ms load")
    print(f"{'strategy':50} {'rows':>6} {'time':>8} {'model loads':>12}  batches")
    totals = {}
    for kind, label, n in [("naive", "Map(): load the model per element", 200),
                           ("setup", "DoFn.setup(): load once, score per element", N),
                           ("runinference", "RunInference(ModelHandler): load once, batched", N)]:
        dt = run(kind, n)
        c, batches, tot = read_logs()
        totals[kind] = tot
        b = f"{len(batches)} batches, {min(batches)}..{max(batches)} rows" if batches else "-"
        print(f"  {label:48} {n:>6,} {dt:7.2f}s {c['load']:>12}  {b}")
    assert totals["setup"] and totals["runinference"] and abs(totals["setup"][0] - totals["runinference"][0]) < 1e-6
    os.rmdir(LOG)
    print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
apache_beam 2.77.0; linear model with 64 features, simulated 50 ms load
strategy                                             rows     time  model loads  batches
  Map(): load the model per element                   200   10.83s          200  -
  DoFn.setup(): load once, score per element        4,000    1.36s            1  -
  RunInference(ModelHandler): load once, batched    4,000    1.39s            1  11 batches, 64..512 rows
ALL ASSERTIONS PASSED
```

* Loading the model inside the per-element function costs **~54 ms per element** (200 loads for 200 rows). This is the most common Beam ML anti-pattern.
* `DoFn.setup` and `RunInference` both load once. RunInference adds batching (here 11 batches of 64–512 rows), so the model sees one matmul per batch. With a toy 64-feature linear model the gain is small; with real models (ONNX, PyTorch) per-call framework overhead and GPU efficiency make batching the dominant factor (Folders 05–07).

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 ⚡ | Dataflow job costs 10× the estimate | High vCPU on SDK harness; low throughput per core | Per-element Python overhead on tiny elements | Batch (`BatchElements`, batched DoFns, arrays as elements); move logic into SQL transforms or Java where possible | Throughput SLO per vCPU in load tests |
| F2 🔥 | Workers OOM after scaling up | Each SDK process holds its own model copy | `load_model` per process × processes per VM | `share_model_across_processes`, `large_model=True`, fewer harness processes per VM | Budget memory as model size × processes |
| F3 | Model reloaded constantly | Startup latency per element; high GCS reads | Loading in `process` or `start_bundle` | `setup` or RunInference | Lint for model loads outside `setup` |
| F4 | Lost writes at shutdown | Records missing after drain | Flushing in `teardown` (best effort) | Flush in `finish_bundle`; idempotent sinks | Never put correctness in `teardown` |
| F5 ⚡ | A Reshuffle or GroupByKey stage is the bottleneck | Data-plane bytes high; ~20–30 µs/element | Fusion break on many tiny elements | Reshuffle batches or keys; combine before GBK (`CombinePerKey`) | Inspect the fused stage graph in the Dataflow UI |
| F6 🔥 | Local test downloads and runs an unexpected binary | `INFO:PrismRunner`, `~/.apache_beam/cache/prism` | Beam ≥ 2.6x DirectRunner delegates to the Prism (Go) runner | Pin `runner=FnApiRunner()` (or vet and mirror Prism) | Supply-chain policy for runtime-downloaded tools |
| F7 | Multi-process local runs fail on Windows | `Worker subprocess exited with return code 1` | Unquoted `sys.executable` with a space, launched via `shell=True` | Run Python from a path without spaces (or its 8.3 short name) | CI on the platforms developers use |
| F8 | Batched DoFn no faster than per-element | Profile shows batch conversion | Producer emits elements; Beam re-batches and explodes | `yields_batches` producers; keep consumers batched | Benchmark end to end, not per transform |

**Debugging toolkit.** `--direct_running_mode=in_memory|multi_threading|multi_processing` locally. Beam Metrics (counters, distributions; as `batch_size` in §2.1) for in-pipeline telemetry. The Dataflow UI's fused-stage view and "data freshness" / "system lag" for streaming, and Cloud Profiler for SDK harness CPU. `--experiments=enable_stackdriver_agent_metrics` and worker logs for per-harness memory.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Explain Runner v2 and the Fn API to someone who knows Dataflow only as a black box."</b></summary>

**Initial Prompt.** Why does a Python Beam pipeline on Dataflow have a different performance profile from a Java one?

**L5 Answer.** "Python is slower than Java."

**Why L5 Crashes at Scale.** "Python is slower" doesn't tell you what to fix. The cost is concentrated at specific boundaries (per-element handling in the SDK harness, data-plane crossings at fusion breaks), and teams that don't see the architecture can't target them.

**L7 Principal Defense.** Runner v2 splits execution into a C++ runner harness (shuffle, windowing state, timers, I/O to Streaming Engine) and SDK harness processes that run your DoFns. They talk over the Fn API: a control plane sending `ProcessBundleRequest`s, a data plane streaming coder-encoded elements, a state API for side inputs and user state, and logging and progress. Within a fused stage Python DoFns call each other directly (~3 µs per element measured). Crossing a stage boundary costs encoding plus gRPC (~20–30 µs per element for a Reshuffle measured). So design Python pipelines with few fusion breaks, combiners before GroupByKey, batched elements, and heavy per-element logic vectorized, or moved to SQL transforms or Java cross-language transforms.

</details>

<details><summary><b>Q2 · "Where do you load a 2 GB model in a Beam pipeline?"</b></summary>

**Initial Prompt.** A streaming pipeline scores events with a large PyTorch model on Dataflow GPU workers.

**L5 Answer.** "In `setup()`, so it loads once."

**Why L5 Crashes at Scale.** "Once" means once per DoFn *instance*, and a worker runs several SDK harness processes and threads. That's 2 GB × processes (sometimes × threads) per VM: OOM, or a GPU holding several model copies.

**L7 Principal Defense.** Use `RunInference` with a model handler and `large_model=True` / `share_model_across_processes`, so one copy per VM is served to all processes through a shared-memory or multi-process manager. Size workers with `--number_of_worker_harness_threads` and set the experiment that limits SDK containers when the model must sit on one GPU. Batch with `batch_elements_kwargs` tuned to GPU memory and the latency SLO. Measured on the small scale: load-per-element was 54 ms per row, and setup or RunInference loaded exactly once. Add a canary that checks per-VM memory and the model-load count metric after each deploy.

</details>

<details><summary><b>Q3 · "Our Python Beam batch job costs 10× the Java equivalent. Make it cheaper without rewriting in Java."</b></summary>

**Initial Prompt.** 20 B small JSON events per day, parse → enrich → aggregate.

**L5 Answer.** "Use more workers, or bigger machines."

**Why L5 Crashes at Scale.** Cost is per-element overhead × 20 B. More workers multiply cost linearly, and the bottleneck (Python per element, fusion-break encoding) stays.

**L7 Principal Defense.** Attack per-element cost. Read in batches (an Arrow/Parquet source or `ReadFromText` → `BatchElements`). Parse vectorized (orjson into pyarrow, or the batched DoFn path measured 4.3× faster than per-element). Combine before shuffles (`CombinePerKey` with a `CombineFn` so GroupByKey moves partial aggregates, not raw events). Use Beam SQL or cross-language Java transforms for the relational parts. Reshuffle only where you need parallelism or checkpoint semantics. Then validate with a cost-per-million-elements metric in a load test at production element size.

</details>

<details><summary><b>Q4 · "What does `teardown()` guarantee?"</b></summary>

**Initial Prompt.** A DoFn buffers writes and flushes them in `teardown()`.

**L5 Answer.** "It runs when the worker finishes, so the data gets flushed."

**Why L5 Crashes at Scale.** `teardown` is best effort. Workers are preempted, autoscaled down or crash, and on those paths it may never run, so buffered records are lost silently. Retries of a bundle can also re-run `process` without a matching teardown.

**L7 Principal Defense.** Treat the bundle as the unit of durability. Buffer in `start_bundle`, flush in `finish_bundle`, and make the sink idempotent (deterministic IDs, upserts), because bundles can be retried. Use `teardown` only for releasing resources (connections, threads). For exactly-once effects use Beam's sink transforms with built-in idempotency or two-phase commit, or write to a staging location and commit atomically.

</details>

<details><summary><b>Q5 · "Should we use Beam's batched DoFn API everywhere?"</b></summary>

**Initial Prompt.** A team converts all DoFns to `process_batch` to get vectorization.

**L5 Answer.** "Yes. Batched DoFns are always faster."

**Why L5 Crashes at Scale.** They're only faster when batches flow end to end. A batched DoFn between per-element transforms makes Beam build batches from elements and explode them again, which was measured during this file's development as no faster than per-element.

**L7 Principal Defense.** Batch at the source (`yields_batches` producers, or Arrow or Parquet readers emitting record batches), keep consecutive transforms batch-aware, and explode only at sinks or aggregations. Measured end to end: ~4.3× faster than per-element in-process. For simple pipelines, ndarrays (or Arrow tables) *as elements* achieve the same with less magic. Verify with a per-transform profile, and keep per-element DoFns where logic is branchy and data is small.

</details>

<details><summary><b>Q6 · "Your local Beam test just downloaded and executed a binary. Is that a problem?"</b></summary>

**Initial Prompt.** Security flags that CI runners fetch `apache_beam-v2.77.0-prism-windows-amd64` at test time.

**L5 Answer.** "It's from Apache, so it's fine."

**Why L5 Crashes at Scale.** Runtime-downloaded executables bypass dependency pinning, SBOMs and vulnerability scanning. They also make CI depend on network access to the release host, and they change behaviour between Beam versions without any code change. It happened here: the default `DirectRunner` delegated to Prism.

**L7 Principal Defense.** Make runner choice explicit. Pin `runner=FnApiRunner()` (pure Python) for unit tests, or vendor and verify the Prism binary (checksum, internal mirror, the `prism_location` option) if you want its fidelity. Block egress in CI so surprises fail loudly, and add a check that `~/.apache_beam/cache` doesn't appear, like the harness here. Record the decision in the supply-chain policy for every framework that downloads tools at run time (Beam Prism, some ML libraries' model hubs).

</details>

<details><summary><b>Q7 · "Beam vs PySpark vs Ray for a Python-heavy ML feature pipeline?"</b></summary>

**Initial Prompt.** Choose an engine for batch plus streaming features with Python model scoring.

**L5 Answer.** "Spark, because it's the most popular."

**Why L5 Crashes at Scale.** The choice hinges on streaming semantics, Python hop costs and model serving. Spark's Python UDF hop (~53–400 ns per row measured), Beam's per-element SDK cost (~3 µs) and Ray's task overhead (~200 µs per task, 04.3) imply different designs.

**L7 Principal Defense.** Beam on Dataflow: unified batch and streaming with event-time windows, exactly-once, managed autoscaling, RunInference. Best when streaming correctness matters, provided elements are batched. Spark: SQL-heavy batch, mature lakehouse integration, Arrow UDFs. Best when most logic is relational. Ray: Python-native distributed compute with shared-memory objects and actors (04.3). Best for ML-heavy, stateful, GPU workloads (batch inference, training data loading). Many platforms combine them: Spark or Beam for features into a lakehouse, Ray for training and batch inference over Arrow and Parquet.

</details>

<details><summary><b>Q8 · "How do you measure where time goes in a Python Beam pipeline?"</b></summary>

**Initial Prompt.** A pipeline misses its SLA; the team doesn't know which transform is slow.

**L5 Answer.** "Add timing logs in every DoFn."

**Why L5 Crashes at Scale.** Per-element logging adds the very overhead you're measuring, floods logs, and misses runner-side costs (shuffles, data-plane encoding, worker start-up).

**L7 Principal Defense.** Use Beam Metrics (counters and distributions, aggregated by the runner across workers, as `batch_size` in §2.1), the Dataflow stage view (wall time per fused stage, data-plane bytes), Cloud Profiler on SDK harness CPU, and local reproduction with `FnApiRunner` in in-memory vs multi-process mode to separate Python compute from data-plane cost (measured ~3 µs per element in-stage against ~20–30 µs per Reshuffle element). Fix the top stage, re-measure, repeat.

</details>

---

## 5. Invariants Checklist

- [ ] Beam pipelines are portable graphs. Runners talk to Python SDK harnesses over the Fn API (control, data, state, logging).
- [ ] Within a fused stage, DoFns call each other directly (~3 µs per element here). Fusion breaks encode and cross the data plane (~20–30 µs per element).
- [ ] `setup` per DoFn instance, `start_bundle`/`finish_bundle` per bundle; `teardown` is best effort.
- [ ] Batching wins only end to end (~4.3× here). Don't feed batched DoFns from per-element producers.
- [ ] Load models once (`setup`/RunInference), share across processes for large models, batch inference calls.
- [ ] Pin the runner. Beam 2.77's DirectRunner may download and run Prism.
- [ ] Windows local multi-process mode needs a Python path without spaces.

---

## 6. References

- Beam portability framework (Runner API, Fn API) — https://beam.apache.org/roadmap/portability/
- Fn API design notes (`beam_fn_api.proto`) — https://github.com/apache/beam/blob/master/model/fn-execution/src/main/proto/org/apache/beam/model/fn_execution/v1/beam_fn_api.proto
- Dataflow Runner v2 — https://cloud.google.com/dataflow/docs/runner-v2
- Beam programming guide, DoFn lifecycle — https://beam.apache.org/documentation/programming-guide/#dofn
- Batched DoFns — https://beam.apache.org/documentation/programming-guide/#batched-dofns
- RunInference — https://beam.apache.org/documentation/ml/about-ml/
- Large models in RunInference (`large_model`, shared models) — https://beam.apache.org/documentation/ml/large-language-modeling/
- Prism runner — https://beam.apache.org/documentation/runners/prism/
- Python FnApiRunner source — https://github.com/apache/beam/tree/master/sdks/python/apache_beam/runners/portability/fn_api_runner
- T. Akidau et al., "The Dataflow Model", PVLDB 8(12), 2015 — https://www.vldb.org/pvldb/vol8/p1792-Akidau.pdf
