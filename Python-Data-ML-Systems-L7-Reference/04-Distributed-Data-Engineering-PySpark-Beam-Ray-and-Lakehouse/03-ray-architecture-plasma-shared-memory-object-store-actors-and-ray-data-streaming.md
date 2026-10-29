# 04.3 · Ray Architecture: Shared-Memory Object Store, Tasks & Actors, and Ray Data Streaming

> **Folder 04 · Distributed Data Engineering: PySpark, Beam, Ray & Lakehouse**
> **Measured on:** Ray 2.59.0 (single node, `num_cpus=4`, dashboard off), Ray Data, pyarrow 26.0.0, NumPy 2.5.4, CPython 3.14.5, i5-11260H, 16 GB, Windows 11. Ray also detected the laptop's RTX 3050 (4 GB), used in Folders 06–07.
> **Design sources:** the Ray architecture whitepaper (ownership, object store, scheduling), the Ray Data user guide (streaming execution, blocks, `map_batches`), and `ray.cluster_resources()` from these runs.
> ⚠ Ray writes `~/.ray/auth_token` and session logs under the temp directory on first start (observed). Clean them up on shared machines.

---

## 0. Orientation & the JVM/C++ Bridge

Ray is a **distributed runtime for Python functions and objects**: tasks (stateless remote functions), actors (stateful remote objects) and a per-node **shared-memory object store** holding immutable objects that any local worker maps without copying. Ray Data builds a streaming dataset engine on top (blocks are Arrow tables in the object store). Where PySpark puts Python behind a JVM (04.1) and Beam behind a portable runner (04.2), Ray makes Python the control plane and keeps bulk data in shared memory: the zero-copy design from 01.3 and 02.3, generalized to a cluster.

| Concept | Ray | JVM analogue | C++ analogue |
|---|---|---|---|
| Remote function | `@ray.remote def f` → task | Akka / Spark task | gRPC job |
| Stateful service | `@ray.remote class A` → actor (one process, ordered calls) | Akka actor, Orleans grain | a service process |
| Distributed reference | `ObjectRef` with an owner (the creating worker) | Spark broadcast / RDD block id | `shared_ptr` to remote memory |
| Node-local data plane | shared-memory object store (Plasma lineage), zero-copy reads | Spark block manager (copies into the JVM heap) | `mmap`ed shared segments |
| Control plane | GCS (global control service) + raylet per node (scheduler + object manager) | YARN RM + NodeManager | — |
| Dataset engine | Ray Data (streaming, Arrow blocks) | Spark DataFrame | Velox pipelines |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 Components

```text
 head node: GCS (cluster metadata, actors, placement groups, job table)
 every node:
   raylet  = local scheduler (leases workers, schedules tasks by resources)
           + object manager (pulls/pushes objects between nodes, spills to disk)
   shared-memory object store  (capacity measured here: 2.0 GiB)
   worker processes (Python), one per concurrently running task or actor
 driver: your script; it OWNS the objects and tasks it creates (ownership-based reference counting)
```

**Ownership.** The worker that creates an object (via `ray.put` or a task's return value) is its owner. It tracks references, location and lineage. When the owner dies its objects are lost (lineage reconstruction can recompute task outputs, not `ray.put` objects). This design takes metadata off the GCS hot path, which is why small-task overhead is ~200 µs rather than milliseconds.

### 1.2 Zero-copy reads from the object store

```text
 ray.put(ndarray)  -> serialize with pickle protocol 5: the 8 B/element buffer is written ONCE into shared memory
                      (out-of-band buffer, no Python object per element)
 ray.get(ref) in any worker on the node
                   -> map the shared segment; np.ndarray is rebuilt as a VIEW over it: writeable=False
                      cost ~0.3 ms whether the array is 16 MiB or 512 MiB (measured)
 task.remote(big_array)    -> Ray implicitly ray.put()s the argument PER CALL (another copy each time)
 task.remote(ref)          -> passes the reference; workers map the same pages
```

Each worker's private memory stayed at ~96 MiB while reading the 256 MiB array. The array is mapped shared memory and isn't charged to each process again: the measured version of "32 workers read one 20 GB tensor with zero copies". Objects are **immutable**, which is what makes sharing safe; writing to a `ray.get` array raises, so call `.copy()` first.

### 1.3 Ray Data: blocks, operators, streaming

```text
 read_parquet (8 files) -> ReadParquet tasks -> blocks (Arrow tables, in the object store)
   -> MapBatches(fn) tasks (fused with the read when possible) -> blocks
   -> consumer: iter_batches() / write_parquet() / aggregate
 streaming executor: operators run concurrently with bounded in-flight blocks per operator
   (backpressure keeps object-store use bounded; the first batch arrives before the whole dataset is read)
 map(fn)          -> fn(dict per row): Arrow -> Python objects per row -> back
 map_batches(fn)  -> fn(batch as numpy dict / pyarrow.Table / pandas): one call per block slice
```

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 The object store, by measurement

```python
"""ray_object_store_zero_copy.py - Ray's shared-memory object store: put once, read everywhere without copying.

A: ray.put cost vs size, and ray.get of a NumPy array (a read-only view into the object store, not a copy).
B: 4 tasks reading a 256 MiB array passed by ObjectRef vs passed by value (Ray re-serializes it per call).
C: what each worker process pays in private memory to read the shared array.
D: scheduling overhead: 2,000 tiny tasks vs one task per batch; an actor call.
"""
import os
import time

import numpy as np
import psutil
import ray

ray.init(num_cpus=4, include_dashboard=False, log_to_driver=False, logging_level="ERROR")
MiB = 2**20


def timed(fn):
    t0 = time.perf_counter()
    r = fn()
    return r, time.perf_counter() - t0


@ray.remote
def total(a):
    m = psutil.Process().memory_info()
    return float(a[::4096].sum()), a.flags.writeable, os.getpid(), getattr(m, "private", m.rss)


@ray.remote
def noop(x):
    return x


@ray.remote
class Counter:
    def __init__(self):
        self.n = 0

    def add(self, k):
        self.n += k
        return self.n


print(f"ray {ray.__version__}; object store capacity {ray.cluster_resources()['object_store_memory'] / 2**30:.1f} GiB")
print("== A. put / get cost vs size")
for mb in (16, 128, 512):
    arr = np.ones(mb * MiB // 8)
    ref, t_put = timed(lambda: ray.put(arr))
    got, t_get = timed(lambda: ray.get(ref))
    print(f"  {mb:4} MiB: ray.put {t_put * 1e3:7.1f} ms ({mb / 1024 / t_put:5.1f} GiB/s)   ray.get {t_get * 1e3:6.2f} ms  "
          f"-> writeable={got.flags.writeable}, shares the buffer: {got.base is not None}")
    del got, ref

print("== B. four tasks read a 256 MiB array")
big = np.random.default_rng(0).random(256 * MiB // 8)
ray.get([noop.remote(i) for i in range(8)])               # start the worker processes first
ref = ray.put(big)
(res_ref, t_ref) = timed(lambda: ray.get([total.remote(ref) for _ in range(4)]))
(res_val, t_val) = timed(lambda: ray.get([total.remote(big) for _ in range(4)]))
expect = float(big[::4096].sum())
assert all(abs(r[0] - expect) < 1e-6 for r in res_ref + res_val)
print(f"  by ObjectRef (one put, shared): {t_ref * 1e3:7.1f} ms; workers see writeable={res_ref[0][1]}")
print(f"  by value (4 implicit puts)    : {t_val * 1e3:7.1f} ms")

print("== C. private memory of each worker process while it reads the shared 256 MiB array")
pids = sorted({r[2] for r in res_ref})
print(f"  {len(pids)} worker processes; private bytes each: "
      f"{', '.join(f'{r[3] / MiB:.0f} MiB' for r in sorted(res_ref, key=lambda r: r[2]))}")
print("  (the array itself is mapped shared memory: it is not counted again per worker)")

print("== D. scheduling overhead")
_, t_tiny = timed(lambda: ray.get([noop.remote(i) for i in range(2000)]))
_, t_batch = timed(lambda: ray.get([noop.remote(list(range(i, i + 500))) for i in range(0, 2000, 500)]))
c = Counter.remote()
ray.get(c.add.remote(1))
_, t_actor = timed(lambda: ray.get([c.add.remote(1) for _ in range(2000)]))
print(f"  2,000 tiny tasks       : {t_tiny * 1e3:7.1f} ms  ({t_tiny / 2000 * 1e6:6.0f} us per task)")
print(f"  4 tasks x 500 items    : {t_batch * 1e3:7.1f} ms")
print(f"  2,000 actor method calls: {t_actor * 1e3:7.1f} ms  ({t_actor / 2000 * 1e6:6.0f} us per call, ordered on one actor)")
ray.shutdown()
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
ray 2.59.0; object store capacity 2.0 GiB
== A. put / get cost vs size
    16 MiB: ray.put   150.5 ms (  0.1 GiB/s)   ray.get   0.28 ms  -> writeable=False, shares the buffer: True
   128 MiB: ray.put    13.7 ms (  9.1 GiB/s)   ray.get   0.28 ms  -> writeable=False, shares the buffer: True
   512 MiB: ray.put    50.8 ms (  9.8 GiB/s)   ray.get   0.26 ms  -> writeable=False, shares the buffer: True
== B. four tasks read a 256 MiB array
  by ObjectRef (one put, shared):    93.3 ms; workers see writeable=False
  by value (4 implicit puts)    :   186.4 ms
== C. private memory of each worker process while it reads the shared 256 MiB array
  4 worker processes; private bytes each: 96 MiB, 96 MiB, 96 MiB, 96 MiB
  (the array itself is mapped shared memory: it is not counted again per worker)
== D. scheduling overhead
  2,000 tiny tasks       :   510.1 ms  (   255 us per task)
  4 tasks x 500 items    :     3.4 ms
  2,000 actor method calls:   405.0 ms  (   203 us per call, ordered on one actor)
ALL ASSERTIONS PASSED
```

* **A:** `ray.put` runs at ~9–10 GiB/s, one memory copy into shared memory. The first put is slower (~150 ms) because the store's pages are committed then. `ray.get` is **~0.3 ms at every size**: a view, not a copy.
* **B:** passing the 256 MiB array *by value* to 4 tasks re-puts it on every call (~2× slower than one `put` plus refs here, and N× the store usage). Always `put` once and pass the ref.
* **C:** workers read shared pages without private copies.
* **D:** ~200–255 µs per tiny task or actor call. A task should carry milliseconds of work at least, so batch fine-grained work (4 tasks × 500 items: ~3 ms against ~500 ms for 2 000 tiny tasks).

### 2.2 Ray Data: per-row `map` vs `map_batches`, streamed

```python
"""ray_data_streaming.py - Ray Data: per-row map() vs map_batches() over a Parquet dataset, streamed through tasks.

Ray Data splits the dataset into blocks (Arrow tables in the object store), runs operators as tasks, and
streams blocks between operators with backpressure. The per-row API pays Python-object conversion per row;
map_batches hands each task a whole block as NumPy or PyArrow.
"""
import os
import shutil
import tempfile
import time

import numpy as np
import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.parquet as pq
import ray

ray.init(num_cpus=4, include_dashboard=False, log_to_driver=False, logging_level="ERROR")
ctx = ray.data.DataContext.get_current()
ctx.enable_progress_bars = False
N = 1_000_000
tmp = tempfile.mkdtemp()
rng = np.random.default_rng(0)
for i in range(8):                                        # 8 files -> at least 8 read tasks / blocks
    n = N // 8
    pq.write_table(pa.table({"id": np.arange(i * n, (i + 1) * n), "price": rng.random(n) * 100,
                             "qty": rng.integers(1, 10, n)}), os.path.join(tmp, f"part-{i}.parquet"))


def per_row(r):
    return {"rev": r["price"] * r["qty"]}


def batch_numpy(b):
    return {"rev": b["price"] * b["qty"]}


def batch_arrow(t):
    return pa.table({"rev": pc.multiply(t["price"], t["qty"])})


def run(label, build):
    ds = build(ray.data.read_parquet(tmp))
    t0 = time.perf_counter()
    total = ds.sum("rev")
    dt = time.perf_counter() - t0
    print(f"  {label:44} {dt * 1e3:8.0f} ms  {dt / N * 1e6:6.2f} us/row  sum={total:,.1f}")
    return total, dt


print(f"ray {ray.__version__}; {N:,} rows in 8 Parquet files; revenue = price * qty, then sum")
r1, t1 = run("map(per_row)  (dict per row)", lambda ds: ds.map(per_row))
r2, t2 = run("map_batches(batch_format='numpy')", lambda ds: ds.map_batches(batch_numpy, batch_format="numpy"))
r3, t3 = run("map_batches(batch_format='pyarrow')", lambda ds: ds.map_batches(batch_arrow, batch_format="pyarrow"))
assert abs(r1 - r2) < 1e-6 * r1 and abs(r2 - r3) < 1e-6 * r2
print(f"  map_batches is {t1 / t2:.0f}x (numpy) / {t1 / t3:.0f}x (pyarrow) faster than per-row map")

print("== streaming consumption: iter_batches() pulls blocks as they are produced")
ds = ray.data.read_parquet(tmp).map_batches(batch_numpy, batch_format="numpy")
t0 = time.perf_counter()
first, rows, nb = None, 0, 0
for b in ds.iter_batches(batch_size=65_536, batch_format="numpy"):
    if first is None:
        first = time.perf_counter() - t0
    rows += len(b["rev"])
    nb += 1
print(f"  first batch after {first * 1e3:.0f} ms, {nb} batches / {rows:,} rows after "
      f"{(time.perf_counter() - t0) * 1e3:.0f} ms (consumer never holds the whole dataset)")
assert rows == N
ray.shutdown()
shutil.rmtree(tmp)
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
ray 2.59.0; 1,000,000 rows in 8 Parquet files; revenue = price * qty, then sum
  map(per_row)  (dict per row)                     6413 ms    6.41 us/row  sum=250,203,266.9
  map_batches(batch_format='numpy')                1919 ms    1.92 us/row  sum=250,203,266.9
  map_batches(batch_format='pyarrow')              1236 ms    1.24 us/row  sum=250,203,266.9
  map_batches is 3x (numpy) / 5x (pyarrow) faster than per-row map
== streaming consumption: iter_batches() pulls blocks as they are produced
  first batch after 122 ms, 16 batches / 1,000,000 rows after 275 ms (consumer never holds the whole dataset)
ALL ASSERTIONS PASSED
```

* `map_batches` is **3× (NumPy) to 5× (pyarrow) faster** than per-row `map` on the same pipeline, and the per-row path also allocates a dict per row.
* `iter_batches` delivered the first batch after ~120–140 ms and all 16 batches in under 0.3 s. The consumer (a training loop, a writer) never holds the whole dataset. This is how Ray Data feeds GPUs in Folder 08.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Object store fills; "spilling objects to disk"; tasks slow down | `ray memory` shows huge pinned objects | ObjectRefs kept alive (lists of refs, cached results) | Drop refs, `del`, release results promptly; stream with Ray Data | Track `ray memory --stats-only` in load tests |
| F2 | Memory grows with fan-out | Store usage ∝ number of calls | Large arguments passed by value (an implicit `put` per call) | `ref = ray.put(x)` once; pass `ref` | Lint: no large literals or arrays in `.remote(...)` |
| F3 ⚡ | Cluster busy, little useful work | Millions of sub-millisecond tasks; GCS/raylet CPU high | Task granularity too fine (~200 µs overhead) | Batch work per task; use actors or Ray Data | Aim for ≥ 10–100 ms per task |
| F4 | `ValueError: assignment destination is read-only` | Writing to a `ray.get` array | Objects are immutable shared memory | `.copy()` before mutating, or return new arrays | Treat object-store data as read-only |
| F5 🔥 | Lost objects after a node failure | `ObjectLostError` / `OwnerDiedError` | The owner process died; `ray.put` objects have no lineage | Recreate from source; checkpoint to durable storage; keep owners long-lived | Don't make short-lived workers own long-lived objects |
| F6 | One actor is the bottleneck | Its queue grows; calls serialized | Actors process calls in order on one process | Shard into an actor pool; async actors; batch calls | Load-test per-actor throughput (~200 µs per call here) |
| F7 ⚡ | Ray Data pipeline slower than pandas | Per-row `map`, Python dict conversions | Row-wise API | `map_batches` with pyarrow or NumPy batch formats | Code review rule: no `ds.map` on hot paths |
| F8 | GPU workers starve | Low GPU utilization; CPU preprocessing is the bottleneck | Input pipeline not overlapped or too few CPU actors | Separate CPU preprocessing actors from GPU actors, with streaming backpressure | Measure the batches/s the trainer actually consumes |

**Debugging toolkit.** `ray status` and `ray memory` (references, sizes, pinning reasons), `ray.timeline()` for Chrome-trace task timelines, `ds.stats()` for per-operator Ray Data stats, the dashboard (disabled here) for live task and actor views, `RAY_LOG_TO_STDERR=1` and session logs under the temp `ray/` directory.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "How do 32 worker processes on one node read the same 20 GB array with zero copies?"</b></summary>

**Initial Prompt.** Explain Ray's object store mechanism and its limits.

**L5 Answer.** "Ray uses shared memory, so everything is zero-copy."

**Why L5 Crashes at Scale.** "Everything" is wrong. Only objects with out-of-band buffers (NumPy arrays, Arrow tables, bytes) are zero-copy. Python object graphs are pickled and deserialized per reader. Passing data by value copies per call, and objects are immutable.

**L7 Principal Defense.** `ray.put` serializes with pickle protocol 5, so large buffers are written once into the node's shared-memory store. `ray.get` in any worker maps those pages and rebuilds the array as a read-only view, ~0.3 ms whatever the size (measured 16–512 MiB), with no per-worker private copy (each worker stayed at ~96 MiB private). Limits: the store's capacity (2.0 GiB default here, with spilling to disk beyond), immutability (`.copy()` to mutate), pickled Python objects being copied per reader, and cross-node access copying the object once to each node. Design data as arrays or Arrow, put once, pass refs.

</details>

<details><summary><b>Q2 · "Ray, Spark or multiprocessing for batch inference over 100 M images?"</b></summary>

**Initial Prompt.** GPU batch inference with CPU-heavy decoding and resizing.

**L5 Answer.** "Spark, because it scales; or multiprocessing, because it's simpler."

**Why L5 Crashes at Scale.** Spark's Python UDF hop and per-task model loading make GPU pipelines awkward, and GPUs idle during CPU preprocessing. multiprocessing has no cluster, scheduling or backpressure, and pickles data per hop (01.3: 155–170 ms per 128 MiB).

**L7 Principal Defense.** Use Ray Data: `read_images`/`read_parquet` → `map_batches(decode)` on CPU workers → `map_batches(Model, num_gpus=1, concurrency=N)` as stateful actors that load the model once → `write_parquet`. The streaming executor overlaps CPU and GPU stages with bounded memory (first batch in ~120 ms here). Blocks move through the object store without copies on a node, and batches are columnar (`map_batches` was 3–5× faster than per-row `map`). Size actor pools by measured throughput per stage.

</details>

<details><summary><b>Q3 · "Our Ray job spends more time scheduling than computing. Why?"</b></summary>

**Initial Prompt.** A team submits one Ray task per record, 10 M records.

**L5 Answer.** "Ray's scheduler is slow; add more nodes."

**Why L5 Crashes at Scale.** At ~200–255 µs per task (measured), 10 M tasks cost ~40 minutes of pure overhead before any work, and adding nodes adds scheduling and metadata load rather than removing it.

**L7 Principal Defense.** Make tasks coarse: each should carry ≥ 10–100 ms of work (measured: 4 tasks × 500 items took 3 ms against 0.5 s for 2 000 single-item tasks). Use Ray Data, or chunk inputs (`ray.data.from_items(...).map_batches`), or long-lived actors processing batches. Keep the driver's refs bounded (`ray.wait` loops) so ownership metadata stays small.

</details>

<details><summary><b>Q4 · "What happens to my objects when a worker dies?"</b></summary>

**Initial Prompt.** A long pipeline fails with `OwnerDiedError` after a spot-instance preemption.

**L5 Answer.** "Ray retries tasks, so data should be recovered."

**Why L5 Crashes at Scale.** Ray reconstructs *task outputs* from lineage when their owner is alive. If the **owner** dies, the references it owned become unrecoverable, and `ray.put` objects have no lineage at all.

**L7 Principal Defense.** Keep owners long-lived: the driver or a dedicated coordinator actor creates the important objects, not ephemeral tasks. Checkpoint stage outputs to durable storage (Parquet on object storage) at stage boundaries. Make tasks idempotent so retries are safe (`max_retries`). Use Ray Data or Train abstractions, which handle retries and checkpoints. Run the head node on stable instances; workers can be spot.

</details>

<details><summary><b>Q5 · "Tasks or actors?"</b></summary>

**Initial Prompt.** A feature service needs a 3 GB embedding table and serves 5 k lookups per second.

**L5 Answer.** "Use tasks and pass the table each time."

**Why L5 Crashes at Scale.** Passing 3 GB by value per call is impossible (an implicit put each time), and even by reference each task reloads or reprocesses it. Tasks are stateless, which is the wrong tool for a resident model or table.

**L7 Principal Defense.** Load the table once into an **actor** (or a pool of actors behind a router), or `ray.put` it once and give actors the ref so all actors on a node share the pages. Calls cost ~200 µs each (measured) and run serially per actor, so size the pool from throughput (5 k/s at 1 ms of work each needs ≥ 5–8 actors) or use async actors for I/O-bound calls. Ray Serve (07.3) builds exactly this, with batching and autoscaling.

</details>

<details><summary><b>Q6 · "Why does Ray Data's `map()` run 5× slower than `map_batches()`?"</b></summary>

**Initial Prompt.** The same revenue computation over 1 M Parquet rows takes 6.4 s with `map` and 1.2 s with `map_batches(batch_format='pyarrow')`.

**L5 Answer.** "`map_batches` uses more parallelism."

**Why L5 Crashes at Scale.** Both run on the same workers. The difference is per-row conversion: Arrow → Python dict → Python arithmetic → dict → Arrow, per row. Missing that leads to tuning concurrency when the fix is representation.

**L7 Principal Defense.** Blocks are Arrow tables, so `map_batches(fn, batch_format="pyarrow")` hands `fn` a table slice and pyarrow.compute does the work with no per-row objects (1.24 µs/row here). `batch_format="numpy"` costs a conversion into NumPy arrays but stays vectorized (1.9 µs/row). `map` pays Python object costs per row (6.4 µs/row). Use pyarrow batches for columnar transforms, NumPy for tensor work, and `map` only for genuinely per-row logic on small datasets.

</details>

<details><summary><b>Q7 · "How do you keep a Ray cluster's object store from thrashing?"</b></summary>

**Initial Prompt.** Spill-to-disk messages appear and throughput collapses during a large job.

**L5 Answer.** "Give the object store more memory."

**Why L5 Crashes at Scale.** More store memory delays the problem. The usual cause is references held longer than needed (results collected into lists, refs captured in closures), which pins objects, so the store can't evict and must spill.

**L7 Principal Defense.** Inspect `ray memory` for pinned objects and their reference types. Release refs as soon as consumers finish (`ray.wait` + process + `del`). Stream with Ray Data's bounded in-flight blocks instead of materializing whole datasets with `ray.get(list)`, and size block sizes to fit. Put spill directories on fast local NVMe. Then size the store (default capacity 2.0 GiB here, normally a fraction of node RAM) to the working set the stream actually needs.

</details>

<details><summary><b>Q8 · "Compare Ray's object store with Spark's block manager and Beam's data plane."</b></summary>

**Initial Prompt.** As an architect, explain why Ray was built differently.

**L5 Answer.** "They're all ways to move data between workers."

**Why L5 Crashes at Scale.** The differences decide whether Python ML workloads are efficient. Spark moves data through the JVM (and into Python over sockets), Beam encodes elements through the Fn API, and Ray keeps buffers in node-local shared memory that Python workers map directly.

**L7 Principal Defense.** Spark's block manager stores serialized blocks for JVM executors, and Python sees data only through the UDF socket hop (04.1). Beam's Fn API streams encoded elements between runner and SDK harness (~20–30 µs per element across a shuffle, 04.2). Ray's per-node shared-memory store lets any Python worker read NumPy or Arrow buffers in ~0.3 ms without copies, with ownership-based metadata for low task overhead (~200 µs). Ray is therefore best when Python *is* the compute (ML, simulation, actors on GPUs). Spark and Beam are best when the compute is relational or streaming-semantic and Python is an edge. Hybrid platforms put Spark/Beam in front of the lakehouse and Ray in front of the GPUs.

</details>

---

## 5. Invariants Checklist

- [ ] `ray.put` writes large buffers once into node shared memory; `ray.get` returns read-only views (~0.3 ms at any size here).
- [ ] Pass `ObjectRef`s, never large values, to `.remote()`. By value means a put per call.
- [ ] Objects are immutable; `.copy()` to mutate.
- [ ] A task or actor call costs ~200 µs. Give each task ≥ 10–100 ms of work.
- [ ] Owners matter: if the creating worker dies, its objects are lost. Keep owners long-lived and checkpoint.
- [ ] Use Ray Data `map_batches` (pyarrow/NumPy) over `map` (3–5× here), and stream with `iter_batches`.
- [ ] Release refs promptly. Pinned objects cause spilling.

---

## 6. References

- Ray architecture whitepaper (ownership, object store, scheduling) — https://docs.ray.io/en/latest/ray-contribute/whitepaper.html
- Ray Core, objects and object store memory — https://docs.ray.io/en/latest/ray-core/objects.html
- Ray Core, serialization (pickle 5, zero-copy NumPy) — https://docs.ray.io/en/latest/ray-core/objects/serialization.html
- Ray memory management and spilling — https://docs.ray.io/en/latest/ray-core/scheduling/memory-management.html
- Ray Data key concepts (blocks, streaming execution) — https://docs.ray.io/en/latest/data/key-concepts.html
- Ray Data `map_batches` and batch formats — https://docs.ray.io/en/latest/data/transforming-data.html
- P. Moritz et al., "Ray: A Distributed Framework for Emerging AI Applications", OSDI 2018 — https://www.usenix.org/conference/osdi18/presentation/moritz
- S. Wang et al., "Ownership: A Distributed Futures System for Fine-Grained Tasks", NSDI 2021 — https://www.usenix.org/conference/nsdi21/presentation/wang
- PEP 574, Pickle protocol 5 with out-of-band data — https://peps.python.org/pep-0574/
