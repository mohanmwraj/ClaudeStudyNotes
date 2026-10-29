# 04.1 · PySpark Internals: JVM Driver → Python Worker Socket, Serialization & Arrow UDFs

> **Folder 04 · Distributed Data Engineering: PySpark, Beam, Ray & Lakehouse**
> **Measured on:** PySpark 4.2.1 (local[4]), Temurin JDK 25.0.4, CPython 3.14.5, pandas 3.1.0 (PySpark warns it "does not yet fully support pandas >= 3.0.0"), pyarrow 26.0.0, i5-11260H, Windows 11.
> **Design sources:** PySpark source (`pyspark/sql/udf.py`, `pyspark/worker.py`), Spark SQL physical plans (`BatchEvalPython`, `ArrowEvalPython`, `MapInArrow`) printed from these runs, and the Spark configuration reference.
> ⚠ **Windows specifics:** Spark has no forking Python daemon on Windows, so Python workers are spawned per task. That adds a large fixed cost per query, which the listing measures and separates from the per-row cost.

---

## 0. Orientation & the JVM/C++ Bridge

A PySpark job is a **JVM program driven from Python**. Your Python driver builds a logical plan through Py4J (or, with Spark Connect, ships it as protobuf over gRPC). Catalyst optimizes it, and JVM executors run it. As long as the work is expressed in Spark SQL/DataFrame expressions, Python is never on the data path. The moment you call a Python UDF, every row must leave the JVM, cross a local socket into a Python worker process, be decoded, computed and re-encoded, and come back. Almost every PySpark performance lesson is about that hop.

| Concept | PySpark 4.x | Pure JVM Spark | C++ engines (Velox/Photon) |
|---|---|---|---|
| Plan construction | Python → Py4J → JVM `Dataset` (or Spark Connect protobuf) | Scala/Java API | — |
| Expression evaluation | JVM codegen (Tungsten) | same | vectorized native |
| Python UDF | separate Python worker per executor slot, fed over a socket | n/a | n/a (UDFs fall back) |
| Row path | `BatchEvalPython`: rows pickled in small batches | — | — |
| Columnar path | `ArrowEvalPython` / `MapInArrow`: Arrow IPC record batches (10,000 rows) | Arrow in Spark Connect results | Arrow-native |
| Result to driver | `collect()` via Py4J; `toPandas()` via Arrow if enabled | `collect()` | — |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 The data path of a Python UDF

```text
 Python driver --Py4J--> JVM driver (Catalyst plan, scheduler)
                              | tasks
                              v
 Executor JVM (one per node; N task slots)
   task: scan -> project -> [Python UDF boundary] -> aggregate
            |                       ^
            | rows (UnsafeRow)      | results
            v                       |
   PythonRunner writer thread --- local socket ---> Python worker process (pyspark.worker)
     BatchEvalPython: rows -> pickled batches (Pyrolite)   -> unpickle -> call f(row) per row -> pickle
     ArrowEvalPython: rows -> Arrow RecordBatch (10,000)   -> pyarrow / pandas Series -> vectorized f -> Arrow
     MapInArrow:      partition -> iterator of RecordBatches -> f(iterator) -> RecordBatches
   PythonRunner reader thread <--- results ---
```

Per-row cost on this machine (marginal, after subtracting the fixed per-query cost):

| Path | ns/row (measured) | Why |
|---|---:|---|
| JVM expression | ~5 | codegen'd loop, no boundary |
| `@udf(useArrow=False)` (pickled rows) | ~365–400 | pickle/unpickle every value, one Python call per row |
| `@udf(useArrow=True)` / default in Spark 4.2 | ~90–130 | Arrow transport, but still one Python call per row |
| `@pandas_udf` (Series → Series) | ~53–60 | Arrow transport **and** one vectorized call per batch |
| `mapInArrow` | ~92–96 | Arrow transport; per-batch `pyarrow.compute`, plus building output batches |

**Spark 4.2 makes plain `@udf` Arrow-optimized by default** (`spark.sql.execution.pythonUDF.arrow.enabled = true`, plan node `ArrowEvalPython`). The legacy pickled path needs an explicit `useArrow=False`. A team upgrading from 3.x can get a ~3–4× faster UDF hop without code changes, and can also see subtle type-coercion differences, because Arrow conversion is stricter than pickling.

### 1.2 Fixed costs: workers, imports and the daemon

On Linux, executors start a `pyspark.daemon` that **forks** pre-imported workers, and `spark.python.worker.reuse` keeps them across tasks. On Windows there is no fork, so workers are spawned. Measured here: **~4.3 s fixed per query on the pickled path and ~5.1–5.2 s on Arrow paths** (pandas and pyarrow imports in each worker). That fixed cost is what made the first naive benchmark show every variant at the same ~5.5 s. Production clusters run Linux, but cold starts, autoscaled executors and Spark Connect sessions still pay worker spawn and import costs. Keep worker imports light.

### 1.3 Memory: where a Python UDF lives

```text
 container memory  >= spark.executor.memory            (JVM heap: execution + storage)
                    + spark.executor.memoryOverhead     (off-heap, netty, JVM native)
                    + spark.executor.pyspark.memory      (Python workers; unbounded if unset!)
 per Python worker: an Arrow batch in + an Arrow batch out + whatever your function allocates
 applyInPandas / groupBy().applyInPandas: a WHOLE GROUP is materialized as one pandas DataFrame
```

### 1.4 Benchmarking trap: re-running an action reuses shuffle outputs

The first version of the listing timed `q.collect()` twice on the same DataFrame, and every Python variant reported ~30 ms for 4 M rows, which is impossible. Re-running an action on the *same* Dataset reuses its shuffle map outputs; the expensive stage is skipped and only the final reduce runs. The listing builds a fresh query for every measurement. Treat any "Spark got 100× faster on the second run" claim with suspicion.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 The UDF ladder: one formula, six execution paths

```python
"""pyspark_udf_ladder.py - the same `x * 1.18 + 2` in Spark five ways: JVM expression vs four Python-worker paths.

Each Python UDF runs in Python worker processes fed by the JVM over a local socket. A plain @udf ships rows
pickled in small batches (BatchEvalPython); useArrow=True / @pandas_udf / mapInArrow ship Arrow record batches
(ArrowEvalPython / MapInArrow, spark.sql.execution.arrow.maxRecordsPerBatch rows each).
Each variant runs on 10k rows and on 8M rows (fresh queries: re-running an action on the same DataFrame
reuses its shuffle map outputs). The small run measures the fixed per-query cost (on Windows Spark spawns
Python workers per task: no fork daemon); (big - small) / rows is the marginal cost per row. Also toPandas().
"""
import re
import time
import warnings

warnings.filterwarnings("ignore", message=".*does not yet fully support pandas.*")
import pandas as pd  # noqa: E402
import pyarrow as pa  # noqa: E402
import pyarrow.compute as pc  # noqa: E402
from pyspark.sql import SparkSession, functions as F, types as T  # noqa: E402

spark = (SparkSession.builder.master("local[4]").appName("udf-ladder")
         .config("spark.ui.enabled", "false").config("spark.ui.showConsoleProgress", "false")
         .config("spark.sql.shuffle.partitions", "4").config("spark.python.worker.reuse", "true")
         .getOrCreate())
spark.sparkContext.setLogLevel("ERROR")
N, SMALL = 8_000_000, 10_000


def frame(n):
    return spark.range(0, n, numPartitions=4).withColumn("x", F.col("id") * 0.5)


@F.udf(T.DoubleType(), useArrow=False)                  # force the legacy pickled-row path
def tax_rows(x):
    return x * 1.18 + 2


@F.udf(T.DoubleType())                                  # no useArrow: whatever the session default is
def tax_default(x):
    return x * 1.18 + 2


@F.udf(T.DoubleType(), useArrow=True)
def tax_arrow_udf(x):
    return x * 1.18 + 2


@F.pandas_udf(T.DoubleType())
def tax_pandas(x: pd.Series) -> pd.Series:
    return x * 1.18 + 2


def tax_batches(it):
    for b in it:                                         # pyarrow.RecordBatch per maxRecordsPerBatch rows
        yield pa.RecordBatch.from_arrays([pc.add(pc.multiply(b.column("x"), 1.18), 2)], names=["y"])


variants = {
    "JVM expression  x*1.18+2": lambda d: d.select((F.col("x") * 1.18 + 2).alias("y")),
    "@udf(useArrow=False) pickled rows": lambda d: d.select(tax_rows("x").alias("y")),
    "@udf, default for this Spark": lambda d: d.select(tax_default("x").alias("y")),
    "@udf(useArrow=True)": lambda d: d.select(tax_arrow_udf("x").alias("y")),
    "@pandas_udf (Series->Series)": lambda d: d.select(tax_pandas("x").alias("y")),
    "mapInArrow (RecordBatch iterator)": lambda d: d.select("x").mapInArrow(tax_batches, "y double"),
}


def plan_nodes(q):
    plan = q._jdf.queryExecution().executedPlan().toString()
    found = re.findall(r"(BatchEvalPython|ArrowEvalPython|MapInArrow|PythonMapInArrow|Project)", plan)
    return ", ".join(dict.fromkeys(found))


print(f"Spark {spark.version}, local[4], {N:,} rows; arrow.maxRecordsPerBatch = "
      f"{spark.conf.get('spark.sql.execution.arrow.maxRecordsPerBatch')}, pythonUDF.arrow.enabled = "
      f"{spark.conf.get('spark.sql.execution.pythonUDF.arrow.enabled')}")
print(f"{'variant':36} {'10k rows':>9} {'8M rows':>9} {'marginal':>10}  physical plan nodes")
marg, sums = {}, {}


def run(make, n):
    t0 = time.perf_counter()
    s = make(frame(n)).agg(F.sum("y").alias("s")).collect()[0]["s"]   # fresh query every time
    return time.perf_counter() - t0, s


for label, make in variants.items():
    run(make, SMALL)                                     # warm-up
    t_small, _ = run(make, SMALL)
    t_big, sums[label] = run(make, N)
    marg[label] = (t_big - t_small) / N * 1e9
    print(f"  {label:34} {t_small:8.2f}s {t_big:8.2f}s {marg[label]:7.0f}ns/row  {plan_nodes(make(frame(10)))}")
vals = list(sums.values())
assert max(vals) - min(vals) < 1e-6 * abs(vals[0])
print(f"  marginal cost vs JVM: pickled {marg['@udf(useArrow=False) pickled rows'] / marg['JVM expression  x*1.18+2']:.0f}x, "
      f"Arrow UDF {marg['@udf(useArrow=True)'] / marg['JVM expression  x*1.18+2']:.0f}x, "
      f"pandas_udf {marg['@pandas_udf (Series->Series)'] / marg['JVM expression  x*1.18+2']:.0f}x, "
      f"mapInArrow {marg['mapInArrow (RecordBatch iterator)'] / marg['JVM expression  x*1.18+2']:.0f}x")

print("== toPandas() of 2M rows x 2 columns")
for enabled in ("false", "true"):
    spark.conf.set("spark.sql.execution.arrow.pyspark.enabled", enabled)
    frame(2_000_000).toPandas()
    t0 = time.perf_counter()
    pdf = frame(2_000_000).toPandas()
    print(f"  arrow.pyspark.enabled={enabled:5}  {(time.perf_counter() - t0) * 1e3:8.0f} ms  ({len(pdf):,} rows)")
spark.stop()
print("ALL ASSERTIONS PASSED")
```

Output (one measured run; Windows, local[4]):

```text
Spark 4.2.1, local[4], 8,000,000 rows; arrow.maxRecordsPerBatch = 10000, pythonUDF.arrow.enabled = true
variant                               10k rows   8M rows   marginal  physical plan nodes
  JVM expression  x*1.18+2               0.16s     0.20s       5ns/row  Project
  @udf(useArrow=False) pickled rows      4.27s     7.19s     365ns/row  Project, BatchEvalPython
  @udf, default for this Spark           5.08s     6.13s     131ns/row  Project, ArrowEvalPython
  @udf(useArrow=True)                    5.16s     5.88s      90ns/row  Project, ArrowEvalPython
  @pandas_udf (Series->Series)           5.19s     5.62s      53ns/row  Project, ArrowEvalPython
  mapInArrow (RecordBatch iterator)      5.13s     5.90s      96ns/row  MapInArrow, Project
  marginal cost vs JVM: pickled 75x, Arrow UDF 19x, pandas_udf 11x, mapInArrow 20x
== toPandas() of 2M rows x 2 columns
  arrow.pyspark.enabled=false      5552 ms  (2,000,000 rows)
  arrow.pyspark.enabled=true        205 ms  (2,000,000 rows)
ALL ASSERTIONS PASSED
```

* **The JVM expression is ~75× cheaper per row than a pickled Python UDF, and ~11–20× cheaper than the best Arrow path.** The first rule of PySpark is still to express logic as Spark SQL functions (`F.when`, `F.expr`, built-ins, higher-order functions).
* When Python is unavoidable, a **vectorized** Arrow UDF (`pandas_udf`, or `mapInArrow` with `pyarrow.compute`) cuts the hop ~4–7× against pickled rows. Arrow transport with row-wise Python (`useArrow=True`) gets only part of that.
* **`toPandas()` with Arrow is ~27× faster** (5.5 s → 0.2 s for 2 M rows). Without Arrow, every row becomes a Python `Row` through Py4J.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Executors killed by YARN/K8s with no JVM OOM | Container exceeded memory limits; JVM heap fine | Python workers' memory isn't in `executor.memory` | Set `spark.executor.pyspark.memory`, raise `memoryOverhead`, shrink `arrow.maxRecordsPerBatch` | Size containers as heap + overhead + Python |
| F2 🔥 | `applyInPandas` job OOMs on one task | One task much bigger than the rest | Skewed group materialized whole in pandas | Salt keys, pre-aggregate, or `mapInArrow` with streaming logic | Profile group-size distribution |
| F3 ⚡ | UDF stage dominates the job | Plan shows `BatchEvalPython` | Pickled row UDF | Built-in functions; `pandas_udf`; Arrow-optimized UDFs | Lint UDFs in code review; read `explain()` |
| F4 | Driver OOM or a stall on `collect()`/`toPandas()` | Driver heap or Python memory spikes | Pulling large results to the driver without Arrow | `spark.sql.execution.arrow.pyspark.enabled`; write to Parquet instead | Never collect unbounded results |
| F5 | Task serialization slow; "Task not serializable"; huge closures | Large `pickle` sizes per task | UDF closure captures big objects (models, dicts) | `spark.sparkContext.broadcast`, load in `mapPartitions`, or ship as files | Keep closures small |
| F6 | Results differ after a Spark 3 → 4 upgrade | Type coercion / null handling in UDF outputs | Arrow-optimized UDFs are now the default | Pin `useArrow` explicitly; type UDF return values exactly | Golden tests on UDF outputs |
| F7 | `FutureWarning: PySpark does not yet fully support pandas >= 3.0.0` | Warnings in executor logs (seen here) | Version skew between PySpark and pandas 3 | Pin pandas per PySpark's supported range, or test the UDF paths you use | Environment matrix in CI |
| F8 | "Second run is 100× faster" in a benchmark | Skipped stages in the Spark UI | Shuffle reuse within one Dataset | Fresh DataFrames per run; clear caches | Benchmark hygiene checklist |

**Debugging toolkit.** `df.explain(mode="formatted")` shows `BatchEvalPython` / `ArrowEvalPython` / `MapInArrow`. The Spark UI SQL tab has Python UDF metrics (time spent, rows and bytes sent to and received from Python). `spark.python.profile=true` profiles UDFs, and `py-spy` attaches to Python worker processes. Executor logs are where the Python worker stderr goes.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Explain exactly what happens to a row when a PySpark job calls a Python UDF."</b></summary>

**Initial Prompt.** Walk through the data path of `df.select(my_udf("x"))` on an executor.

**L5 Answer.** "Spark sends the data to Python, runs the function, and sends it back."

**Why L5 Crashes at Scale.** "Sends the data" hides the cost model: serialization format, batch size, threads, process memory. Without it you can't explain why a UDF is 75× more expensive than an expression, or why a pod dies without a JVM OOM.

**L7 Principal Defense.** The executor's `PythonRunner` starts a writer thread that serializes input rows (pickled batches for `BatchEvalPython`, Arrow record batches of `maxRecordsPerBatch` rows for `ArrowEvalPython`/`MapInArrow`) onto a local socket into a Python worker process. The worker decodes, calls the function (per row, or per batch for vectorized UDFs) and streams results back to a reader thread, which converts them to `UnsafeRow`s. Measured marginal costs: ~5 ns/row in the JVM, ~365–400 pickled, ~90–130 Arrow-transport row-wise, ~53–60 `pandas_udf`. Workers live outside the JVM heap, so memory must be budgeted with `spark.executor.pyspark.memory` and overhead. The decision rule is built-ins first, vectorized Arrow UDFs second, row UDFs never in hot paths.

</details>

<details><summary><b>Q2 · "Our UDF job didn't speed up at all with Arrow. Why?"</b></summary>

**Initial Prompt.** A team switched `@udf` to `@pandas_udf` and saw no improvement in a small benchmark.

**L5 Answer.** "Arrow only helps for big data; it's not worth it."

**Why L5 Crashes at Scale.** The benchmark was dominated by fixed costs. Measured here, worker spawn and imports were ~4–5 s per query on Windows, swamping per-row differences, and the second run of the same DataFrame skipped stages entirely. Concluding "Arrow doesn't help" from that leaves the 7× per-row gain on the table at production scale.

**L7 Principal Defense.** Separate fixed and marginal costs. Run each variant on tiny and large inputs with fresh DataFrames, and compute (t_big − t_small)/rows, as the listing does. Then project to production row counts: at 1 B rows, 365 vs 53 ns/row is ~6 core-minutes against ~1, across the cluster. Also check what the default already is: Spark 4.2 makes plain `@udf` Arrow-optimized (`pythonUDF.arrow.enabled = true`), so the upgrade itself may have delivered part of the gain.

</details>

<details><summary><b>Q3 · "Executors keep getting killed by Kubernetes but the Spark UI shows heap usage is fine."</b></summary>

**Initial Prompt.** A PySpark job using `applyInPandas` fails intermittently with exit code 137.

**L5 Answer.** "Increase `spark.executor.memory`."

**Why L5 Crashes at Scale.** Raising the heap makes it *worse*. The JVM grabs more of the container, leaving less for the Python workers, whose memory isn't governed by the heap setting at all. `applyInPandas` materializes entire groups, so one skewed key spikes one worker.

**L7 Principal Defense.** Budget the container as heap + `memoryOverhead` + `pyspark.memory` × concurrent workers. Set `spark.executor.pyspark.memory` so Python allocations fail inside the worker with a clear error rather than via an OOM kill. Reduce `arrow.maxRecordsPerBatch` for wide rows. Fix the skew by salting keys or pre-aggregating, or replace `applyInPandas` with `mapInArrow`, which streams batches instead of materializing groups. Monitor per-task input sizes to catch skew before it pages you.

</details>

<details><summary><b>Q4 · "When should business logic be a UDF at all?"</b></summary>

**Initial Prompt.** A data team writes most transformations as Python UDFs "for readability".

**L5 Answer.** "UDFs are fine if they're vectorized with pandas."

**Why L5 Crashes at Scale.** Even the best vectorized UDF was ~11× the per-row cost of a JVM expression here, and every UDF is an optimizer barrier. Catalyst can't push filters through it, reorder around it, or prune columns it reads opaquely.

**L7 Principal Defense.** Express logic in Spark SQL (built-ins, `CASE`, higher-order functions like `transform`/`filter` on arrays, joins against rules tables). It's faster and optimizable, and engines like Photon or Velox can run it natively. Reserve UDFs for logic that truly needs Python (model inference, complex libraries), and make those vectorized (`pandas_udf`/`mapInArrow`) with heavyweight setup done once per partition. Measure in `explain()` that no `BatchEvalPython` remains on hot paths.

</details>

<details><summary><b>Q5 · "How does Spark Connect change the Python–JVM picture?"</b></summary>

**Initial Prompt.** Should a platform team move notebooks and services to Spark Connect?

**L5 Answer.** "Spark Connect is just a remote version of PySpark."

**Why L5 Crashes at Scale.** It changes the failure and dependency model. The client no longer embeds a JVM (no Py4J), plans travel as protobuf over gRPC, and results come back as Arrow batches. But Python UDFs still run in Python workers next to the server-side executors, so their environment must match server-side.

**L7 Principal Defense.** Spark Connect decouples client lifecycle from the cluster: thin clients, server-side session isolation, upgrades without client JVMs, and Arrow results (the zero-copy-friendly path from 02.3). It doesn't remove the UDF hop. Ship UDF dependencies to the cluster (environment images or `addArtifacts`), keep UDFs vectorized, and budget server-side Python memory as in Q3. It's a good default for notebooks and services; batch pipelines see little change.

</details>

<details><summary><b>Q6 · "Why is `toPandas()` 27× faster with Arrow?"</b></summary>

**Initial Prompt.** Explain the measured difference: 5.5 s against 0.2 s for 2 M rows.

**L5 Answer.** "Arrow is a faster format."

**Why L5 Crashes at Scale.** Without the mechanism you can't predict when Arrow falls back (unsupported types silently revert to the slow path if fallback is enabled) or why the result can still be huge in memory.

**L7 Principal Defense.** Without Arrow, results are collected as JVM rows, serialized through Py4J, rebuilt as Python `Row` objects (an object per row plus boxed values) and then assembled into pandas, so the cost is per row. With Arrow, executors send record batches that pandas wraps as columns, so the cost is per batch. Watch `spark.sql.execution.arrow.pyspark.fallback.enabled`: if a type isn't supported, Spark may fall back to the slow path silently. And prefer writing results to Parquet over pulling them to the driver at all.

</details>

<details><summary><b>Q7 · "A UDF closure makes every task take seconds to deserialize. Diagnose."</b></summary>

**Initial Prompt.** A UDF references a 500 MB lookup dictionary defined in the driver.

**L5 Answer.** "Python is slow at pickling; use a faster serializer."

**Why L5 Crashes at Scale.** The dictionary is pickled into the *task closure* and shipped with every task. With thousands of tasks that's hundreds of GB over the network, and each worker re-unpickles it.

**L7 Principal Defense.** Ship data once per executor, not once per task: `sc.broadcast(lookup)` and read `.value` inside the UDF. Better, convert the lookup to a DataFrame and **join**, which Spark optimizes (broadcast hash join) without Python. For models, load them in `mapInPandas`/`mapInArrow` per partition (or as a cached module global per worker process). Check closure sizes with `len(cloudpickle.dumps(fn))` in tests.

</details>

<details><summary><b>Q8 · "What's your checklist before approving a PySpark job for production?"</b></summary>

**Initial Prompt.** You're the reviewer for a 2 TB/day PySpark pipeline.

**L5 Answer.** "Check that it runs and the output looks right."

**Why L5 Crashes at Scale.** Functional checks miss the cost and stability problems that show up only at scale: UDF hops, skew, driver collects and memory budgets.

**L7 Principal Defense.** Read `explain("formatted")`: no `BatchEvalPython` on hot paths, filters pushed into scans, broadcast joins where expected. Check memory: container = heap + overhead + `pyspark.memory`, with Arrow batch size set for row width. Check skew (task input-size percentiles) and AQE skew-join settings. No `collect()`/`toPandas()` of unbounded data. Closures small, with broadcasts for reference data. Pin versions (Spark, pandas, pyarrow; note PySpark's pandas 3 warning). And benchmarks must use fresh plans (no shuffle reuse) and production-sized data.

</details>

---

## 5. Invariants Checklist

- [ ] Spark SQL expressions never leave the JVM; Python UDFs cross a socket into worker processes.
- [ ] Marginal cost per row here: JVM ~5 ns, pickled UDF ~365–400 ns, Arrow row UDF ~90–130 ns, `pandas_udf` ~53–60 ns.
- [ ] Spark 4.2 plain `@udf` is Arrow-optimized by default (`ArrowEvalPython`); use `useArrow=False` only to reproduce legacy behaviour.
- [ ] Python worker memory is outside the JVM heap. Set `spark.executor.pyspark.memory` and overhead.
- [ ] `applyInPandas` materializes whole groups: skew becomes OOM.
- [ ] `toPandas()` needs Arrow enabled (27× here). Better, write to Parquet.
- [ ] Re-running an action on the same DataFrame can skip stages. Benchmark with fresh plans.
- [ ] Broadcast or join reference data; never capture big objects in UDF closures.

---

## 6. References

- Spark SQL guide, Arrow in PySpark (`pandas_udf`, `mapInArrow`, `maxRecordsPerBatch`) — https://spark.apache.org/docs/latest/api/python/tutorial/sql/arrow_pandas.html
- PySpark `udf` (`useArrow`) — https://spark.apache.org/docs/latest/api/python/reference/pyspark.sql/api/pyspark.sql.functions.udf.html
- Spark configuration (`spark.executor.pyspark.memory`, `memoryOverhead`, `python.worker.reuse`) — https://spark.apache.org/docs/latest/configuration.html
- Spark Connect overview — https://spark.apache.org/docs/latest/spark-connect-overview.html
- Spark source, `PythonRunner` / `ArrowPythonRunner` — https://github.com/apache/spark/tree/master/core/src/main/scala/org/apache/spark/api/python
- PySpark worker (`pyspark/worker.py`) — https://github.com/apache/spark/blob/master/python/pyspark/worker.py
- M. Zaharia et al., "Resilient Distributed Datasets", NSDI 2012 — https://www.usenix.org/conference/nsdi12/technical-sessions/presentation/zaharia
- M. Armbrust et al., "Spark SQL: Relational Data Processing in Spark", SIGMOD 2015, DOI 10.1145/2723372.2742797.
