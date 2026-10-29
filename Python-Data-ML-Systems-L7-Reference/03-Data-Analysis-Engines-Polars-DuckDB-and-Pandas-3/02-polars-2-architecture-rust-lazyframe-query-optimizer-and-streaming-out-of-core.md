# 03.2 · Polars 2 Architecture: Rust LazyFrame, Query Optimizer & Streaming Out-of-Core Engine

> **Folder 03 · Data Analysis Engines: Polars, DuckDB & pandas 3**
> **Measured on:** Polars 2.1.0 (12-thread pool), pandas 3.1.0, pyarrow 26.0.0, CPython 3.14.5, i5-11260H, 16 GB, Windows 11. Peak memory is measured per strategy in a **fresh child process** (`psutil` peak working set).
> **Design sources:** the Polars user guide (lazy API, optimizations, streaming engine), `LazyFrame.explain()` output from these runs, and Polars' `PolarsInefficientMapWarning`.

---

## 0. Orientation & the JVM/C++ Bridge

Polars is a **query engine with a DataFrame API**. Expressions (`pl.col("x") * 2`) build a logical plan in Rust. A `LazyFrame` collects a whole pipeline, optimizes it (pushdowns, pruning, common-subexpression elimination) and executes it on a work-stealing thread pool, without the GIL, over Arrow-style columnar memory. The eager `DataFrame` API runs the same engine one step at a time. Most Polars wins in production come from four things: **never reading what the query doesn't need**, **running on all cores**, **never calling back into Python per row**, and **bounding memory by streaming**. This file measures each one, including where it doesn't help.

| Concept | Polars 2 | JVM analogue | C++ analogue |
|---|---|---|---|
| Expression | `pl.Expr`, a node in a typed expression tree | Spark Catalyst `Expression` | expression templates / an AST |
| Lazy query | `LazyFrame` → logical plan → optimized IR → physical plan | Spark `Dataset` + Catalyst + Tungsten | DuckDB / Velox plans |
| Execution | Rust, work-stealing thread pool (`POLARS_MAX_THREADS`), no GIL | Spark executors (JVM threads) | Velox / folly executors |
| Memory layout | Arrow-compatible columns; strings as BinaryView (Utf8View) | Tungsten `UnsafeRow` (row-oriented) | Arrow C++ / Velox vectors |
| Out-of-core | streaming engine (morsel-driven) + `sink_*` | Spark shuffle spill | DuckDB spilling operators |
| Python UDF | `map_elements` (per value, GIL) / `map_batches` (per Series) | Spark Python UDF (05-style cliff) | — |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 From expressions to an optimized plan

```text
 pl.scan_parquet(path)                         DSL (Python)  -> DslPlan (Rust)
   .filter((pl.col("ts") >= c) & (pl.col("amount") > 50))
   .group_by("country").agg(pl.col("amount").sum())
   .sort("country")
        |  conversion + type resolution -> IR (logical plan arena)
        v
 optimizer passes (run on collect/explain):
   predicate pushdown    filters move into the scan ("SELECTION:"), split/combined, pushed through joins
   projection pushdown   only referenced columns are read ("PROJECT 3/12 COLUMNS")
   slice pushdown        head()/limit() stop the scan early
   simplify / CSE        constant folding, common sub-expressions and sub-plans computed once
   type coercion, join ordering, cluster with_columns ...
        v
 physical plan -> engine: "in-memory" (operator-at-a-time, parallel per operator)
                          "streaming" (morsel-driven pipelines, bounded memory)
                          "gpu" (cuDF-backed, NVIDIA only; not available here)
```

The measured plan in §2.1 shows the passes. The unoptimized plan scans `*/12 COLUMNS` and applies two separate `FILTER` nodes above the scan. The optimized plan has a single scan with `PROJECT 3/12 COLUMNS` and `SELECTION: (amount > 50) & (ts >= 36000000)`. The Parquet reader then uses each row group's footer statistics to skip row groups whose `[min, max]` can't satisfy the predicate (2 of 20 needed here), so most bytes are never decompressed.

### 1.2 Parallelism and the GIL

```text
 Python thread: builds the plan, calls .collect() -> releases the GIL -> waits
 Rust pool (12 threads here; size fixed at import from POLARS_MAX_THREADS or the core count):
   per-column and per-partition tasks: hash aggregation in thread-local tables, then merge
   expressions inside one with_columns/select run in parallel with each other
 map_elements(lambda) -> for EACH value: acquire the GIL, box to PyObject, call, unbox -> serial again
```

Polars' single-thread speed on a hash group-by is roughly pandas' (measured 0.9×). The 3.7× win on this machine is the **thread pool**, which pandas lacks. Every Python UDF throws that away: a lambda per value measured **~60× slower** than the native expression, with Polars itself emitting `PolarsInefficientMapWarning` and suggesting the rewrite.

### 1.3 The streaming engine: morsels, pipelines, sinks

```text
 scan (row-group / morsel source) -> filter -> project -> partial aggregate (per thread) -> merge -> sink
   each thread pulls a MORSEL (a batch of rows), pushes it through the pipeline in cache-sized chunks
   pipeline breakers (sort, join build side, aggregation) hold STATE; everything else streams through
 memory ~ threads x morsel size + operator state      (not ~ input size)
 sink_parquet / sink_ipc / sink_csv: results streamed to disk, never materialized as one DataFrame
```

The decisive term is **operator state**. A group-by with 8 keys has kilobytes of state, so streaming caps memory at the scan buffers (measured: 303 MiB peak against 731 MiB eager). A group-by with 3 M keys has hundreds of MiB of hash-table state *plus* the 3 M-row result, so streaming can't beat eager (measured 947 vs 968 MiB), and per-thread partial tables can even add memory. Streaming bounds memory for **scan-dominated** queries; it doesn't make high-cardinality state disappear.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Trap: `read_parquet` then filter. Pattern: `scan_parquet` and let the optimizer push down

```python
"""polars_lazy_pushdown.py - eager read-then-filter vs a LazyFrame plan with predicate + projection pushdown.

Writes a 4M-row, 12-column Parquet file (20 row groups, sorted `ts`), then answers one question three ways,
each in a fresh child process so peak memory is isolated: eager read_parquet, eager with columns=, and
scan_parquet (lazy). Prints the unoptimized vs optimized plan and the row groups Parquet statistics allow skipping.
"""
import os
import subprocess
import sys
import tempfile
import textwrap

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq

N, RG = 4_000_000, 200_000
rng = np.random.default_rng(0)
cols = {"ts": np.arange(N, dtype=np.int64) * 10, "user_id": rng.integers(0, 50_000, N),
        "country": pa.array(np.array(["US", "IN", "DE", "BR", "JP"])[rng.integers(0, 5, N)]).dictionary_encode(),
        "amount": rng.random(N) * 100}
cols.update({f"f{i}": rng.random(N) for i in range(8)})
tmp = tempfile.mkdtemp()
path = os.path.join(tmp, "events.parquet")
pq.write_table(pa.table(cols), path, row_group_size=RG)
md = pq.ParquetFile(path).metadata
CUTOFF = int(N * 10 * 0.9)                               # the last 10% of the time range
ts_idx = md.schema.names.index("ts")
needed = sum(1 for i in range(md.num_row_groups) if md.row_group(i).column(ts_idx).statistics.max >= CUTOFF)
print(f"Parquet: {N:,} rows x {md.num_columns} columns, {md.num_row_groups} row groups, "
      f"{os.path.getsize(path) / 2**20:.0f} MiB")
print(f"  row groups whose ts max >= cutoff (from footer min/max stats): {needed}/{md.num_row_groups}")

CHILD = textwrap.dedent("""
    import sys, time, psutil, polars as pl
    path, cutoff, mode = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    t0 = time.perf_counter()
    if mode == "eager":
        df = pl.read_parquet(path)
        out = df.filter((pl.col("ts") >= cutoff) & (pl.col("amount") > 50)).group_by("country").agg(
            pl.col("amount").sum()).sort("country")
    elif mode == "eager_cols":
        df = pl.read_parquet(path, columns=["ts", "country", "amount"])
        out = df.filter((pl.col("ts") >= cutoff) & (pl.col("amount") > 50)).group_by("country").agg(
            pl.col("amount").sum()).sort("country")
    else:
        out = (pl.scan_parquet(path).filter((pl.col("ts") >= cutoff) & (pl.col("amount") > 50))
               .group_by("country").agg(pl.col("amount").sum()).sort("country").collect())
    dt = time.perf_counter() - t0
    m = psutil.Process().memory_info()
    peak = getattr(m, "peak_wset", None) or __import__("resource").getrusage(0).ru_maxrss * 1024
    print(f"{dt:.4f} {peak / 2**20:.1f} {round(float(out['amount'].sum()), 2)}")
""")
print(f"{'strategy':52} {'time':>9} {'peak RSS':>10}  result")
results = {}
for label, mode in [("eager read_parquet() then filter", "eager"),
                    ("eager read_parquet(columns=[3 cols]) then filter", "eager_cols"),
                    ("scan_parquet() lazy: pushdown + projection", "lazy")]:
    out = subprocess.run([sys.executable, "-c", CHILD, path, str(CUTOFF), mode], capture_output=True, text=True,
                         check=True).stdout.split()
    dt, peak, total = float(out[0]), float(out[1]), float(out[2])
    results[mode] = (dt, peak, total)
    print(f"  {label:50} {dt * 1e3:7.0f}ms {peak:8.0f}MiB  sum={total:,.2f}")
assert len({r[2] for r in results.values()}) == 1, "all strategies must agree"
assert results["lazy"][1] < results["eager"][1]

import polars as pl  # noqa: E402  (imported after the children so the parent's RSS doesn't matter)

lf = (pl.scan_parquet(path).filter((pl.col("ts") >= CUTOFF) & (pl.col("amount") > 50))
      .group_by("country").agg(pl.col("amount").sum()).sort("country"))
for title, plan in [("unoptimized plan", lf.explain(optimized=False)), ("optimized plan", lf.explain())]:
    print(f"== {title}")
    for line in plan.replace(path, "<events.parquet>").replace(path.replace("\\", "/"), "<events.parquet>").splitlines():
        print(f"  {line}")
os.remove(path)
os.rmdir(tmp)
print("ALL ASSERTIONS PASSED")
```

Output (one measured run; each strategy in its own process):

```text
Parquet: 4,000,000 rows x 12 columns, 20 row groups, 355 MiB
  row groups whose ts max >= cutoff (from footer min/max stats): 2/20
strategy                                                  time   peak RSS  result
  eager read_parquet() then filter                       148ms      686MiB  sum=14,989,701.97
  eager read_parquet(columns=[3 cols]) then filter        44ms      255MiB  sum=14,989,701.97
  scan_parquet() lazy: pushdown + projection              15ms       88MiB  sum=14,989,701.97
== unoptimized plan
  SORT BY [col("country")]
    AGGREGATE[maintain_order: false]
      [col("amount").sum()] BY [col("country")]
      FROM
      FILTER col("amount") > 50.0
      FROM
        FILTER col("ts") >= 36000000
        FROM
          Parquet SCAN [<events.parquet>]
          PROJECT */12 COLUMNS
          ESTIMATED ROWS: 4000000
== optimized plan
  SORT BY [col("country")]
    AGGREGATE[maintain_order: false]
      [col("amount").sum()] BY [col("country")]
      FROM
      simple π 2/2 ["country", "amount"]
        Parquet SCAN [<events.parquet>]
        PROJECT 3/12 COLUMNS
        SELECTION: (col("amount") > 50.0) & (col("ts") >= 36000000)
        ESTIMATED ROWS: 4000000
ALL ASSERTIONS PASSED
```

* Eager read of all 12 columns: ~150–230 ms and **~670–690 MiB** peak.
* Eager with `columns=` (manual projection): ~44 ms and ~240–255 MiB.
* Lazy `scan_parquet`: **~15–32 ms and ~84–88 MiB**, with projection *and* predicate pushdown, and row-group skipping from footer statistics (2 of 20 needed).
* The results are identical (asserted). The plan text is the debugging tool: if `SELECTION:` doesn't appear inside the scan, something blocked pushdown (a UDF in the predicate, a non-deterministic expression, an operation order the optimizer can't reorder).

### 2.2 Where Polars' speed comes from: threads, native expressions, parallel contexts

```python
"""polars_expressions_engine.py - why Polars expressions beat pandas idioms: Rust kernels, no GIL, all cores.

A: a multi-aggregation group-by on 10M rows, pandas 3 vs Polars (default threads vs POLARS_MAX_THREADS=1,
   each in a child process because the pool size is fixed at import).
B: the Python-UDF cliff - map_elements calls back into Python per value (GIL, boxing) vs a native expression.
C: independent expressions in one with_columns run in parallel.
"""
import os
import subprocess
import sys
import textwrap
import time
import warnings

import numpy as np
import pandas as pd
import polars as pl

N = 10_000_000
rng = np.random.default_rng(0)
data = {"user": rng.integers(0, 200_000, N), "amount": rng.random(N) * 100, "qty": rng.integers(1, 10, N)}


def timed(fn, reps=3):
    best, r = float("inf"), None
    for _ in range(reps):
        t0 = time.perf_counter()
        r = fn()
        best = min(best, time.perf_counter() - t0)
    return r, best


print(f"polars {pl.__version__} (thread pool {pl.thread_pool_size()}), pandas {pd.__version__}; {N:,} rows")
print("== A. group_by(user).agg(sum, mean, max, n_unique(qty), len)")
pdf = pd.DataFrame(data)
r_pd, t_pd = timed(lambda: pdf.groupby("user").agg(s=("amount", "sum"), m=("amount", "mean"), mx=("amount", "max"),
                                                     nq=("qty", "nunique"), n=("qty", "size")), reps=1)
df = pl.DataFrame(data)
agg = [pl.col("amount").sum().alias("s"), pl.col("amount").mean().alias("m"), pl.col("amount").max().alias("mx"),
       pl.col("qty").n_unique().alias("nq"), pl.len().alias("n")]
r_pl, t_pl = timed(lambda: df.group_by("user").agg(agg))
check = r_pl.sort("user")
assert np.allclose(check["s"].to_numpy(), r_pd["s"].to_numpy()) and (check["nq"].to_numpy() == r_pd["nq"]).all()
CHILD = textwrap.dedent("""
    import time, numpy as np, polars as pl
    rng = np.random.default_rng(0); N = 10_000_000
    df = pl.DataFrame({"user": rng.integers(0, 200_000, N), "amount": rng.random(N) * 100,
                       "qty": rng.integers(1, 10, N)})
    agg = [pl.col("amount").sum().alias("s"), pl.col("amount").mean().alias("m"),
           pl.col("amount").max().alias("mx"), pl.col("qty").n_unique().alias("nq"), pl.len().alias("n")]
    best = float("inf")
    for _ in range(3):
        t0 = time.perf_counter()
        df.group_by("user").agg(agg)
        best = min(best, time.perf_counter() - t0)
    print(pl.thread_pool_size(), best)
""")
env1 = dict(os.environ, POLARS_MAX_THREADS="1")
threads1, t_pl1 = subprocess.run([sys.executable, "-c", CHILD], env=env1, capture_output=True, text=True,
                                 check=True).stdout.split()
print(f"  pandas 3 groupby.agg                 {t_pd * 1e3:8.0f} ms")
print(f"  Polars, POLARS_MAX_THREADS={threads1:<2}       {float(t_pl1) * 1e3:8.0f} ms  ({t_pd / float(t_pl1):4.1f}x pandas)")
print(f"  Polars, {pl.thread_pool_size()} threads                  {t_pl * 1e3:8.0f} ms  ({t_pd / t_pl:4.1f}x pandas, "
      f"{float(t_pl1) / t_pl:.1f}x from threads)")

print("== B. the Python-UDF cliff (1M rows): amount * 1.1 + 2")
small = df.head(1_000_000)
with warnings.catch_warnings(record=True) as caught:
    warnings.simplefilter("always")
    r_udf, t_udf = timed(lambda: small.select(pl.col("amount").map_elements(lambda x: x * 1.1 + 2,
                                                                             return_dtype=pl.Float64)), reps=1)
first = str(caught[0].message).strip().splitlines()[0] if caught else "no warning"
print(f"  Polars warned: {type(caught[0].message).__name__}: {first}")
r_nat, t_nat = timed(lambda: small.select(pl.col("amount") * 1.1 + 2))
assert np.allclose(r_udf.to_series().to_numpy(), r_nat.to_series().to_numpy())
print(f"  map_elements(lambda)  {t_udf * 1e3:8.1f} ms   (one Python call per value, holding the GIL)")
print(f"  native expression     {t_nat * 1e3:8.1f} ms   ({t_udf / t_nat:.0f}x faster)")

print("== C. six independent expressions in one context")
exprs = [(pl.col("amount") * pl.col("qty")).alias("rev"), pl.col("amount").log1p().alias("la"),
         pl.col("amount").rank().alias("rk"), (pl.col("qty") % 3 == 0).alias("q3"),
         pl.col("amount").cum_sum().alias("cs"), pl.col("user").hash().alias("h")]
_, t_one = timed(lambda: df.with_columns(exprs))
_, t_seq = timed(lambda: [df.with_columns(e) for e in exprs])
print(f"  with_columns(all six) {t_one * 1e3:8.1f} ms  vs six separate with_columns {t_seq * 1e3:8.1f} ms")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
polars 2.1.0 (thread pool 12), pandas 3.1.0; 10,000,000 rows
== A. group_by(user).agg(sum, mean, max, n_unique(qty), len)
  pandas 3 groupby.agg                      887 ms
  Polars, POLARS_MAX_THREADS=1             983 ms  ( 0.9x pandas)
  Polars, 12 threads                       237 ms  ( 3.7x pandas, 4.2x from threads)
== B. the Python-UDF cliff (1M rows): amount * 1.1 + 2
  Polars warned: PolarsInefficientMapWarning: Expr.map_elements is significantly slower than the native expressions API.
  map_elements(lambda)     125.7 ms   (one Python call per value, holding the GIL)
  native expression          2.0 ms   (63x faster)
== C. six independent expressions in one context
  with_columns(all six)    464.9 ms  vs six separate with_columns    598.8 ms
ALL ASSERTIONS PASSED
```

* **A:** on one thread Polars ties pandas on this group-by; on 12 threads it's ~4× faster than itself single-threaded and ~3.7× pandas. Size pods by cores, and remember that `POLARS_MAX_THREADS` is read once, at import.
* **B:** `map_elements` is the Python-UDF cliff, about 60× slower and GIL-serialized. If logic truly needs Python, `map_batches` (one call per Series) or a compiled kernel (Numba / a Polars plugin in Rust) keeps it vectorized.
* **C:** six independent expressions in one `with_columns` run in parallel and beat six separate calls by ~25 %. Group independent expressions into one context.

### 2.3 Streaming and sinks: when bounded memory works, and when it can't

```python
"""polars_streaming_out_of_core.py - the same query on Polars' in-memory engine vs its morsel-driven streaming engine.

Writes a 30M-row Parquet file in batches (never holding it in memory), then in fresh child processes runs a
high-cardinality group-by (3M keys: the hash-table state dominates) and a low-cardinality one (8 keys: the scan
dominates) on the eager, in-memory and streaming engines, plus a streaming filter that sink_parquet()s to disk.
"""
import os
import subprocess
import sys
import tempfile
import textwrap

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq

N, BATCH = 30_000_000, 2_000_000
tmp = tempfile.mkdtemp()
path = os.path.join(tmp, "facts.parquet")
schema = pa.schema([("key", pa.int64()), ("v", pa.float64()), ("cat", pa.int8())])
rng = np.random.default_rng(0)
with pq.ParquetWriter(path, schema) as w:
    for start in range(0, N, BATCH):
        n = min(BATCH, N - start)
        w.write_table(pa.table({"key": rng.integers(0, 3_000_000, n), "v": rng.random(n),
                                "cat": rng.integers(0, 8, n).astype(np.int8)}, schema=schema),
                      row_group_size=500_000)
raw_mb = N * 17 / 2**20
print(f"Parquet: {N:,} rows, {os.path.getsize(path) / 2**20:.0f} MiB on disk, ~{raw_mb:.0f} MiB decoded")

CHILD = textwrap.dedent("""
    import os, sys, time, psutil, polars as pl
    path, mode, out, by = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    q = lambda lf: lf.group_by(by).agg(pl.col("v").sum().alias("s"), pl.len().alias("n"))
    t0 = time.perf_counter()
    if mode == "eager":
        res = q(pl.read_parquet(path).lazy()).collect()
    elif mode == "in-memory":
        res = q(pl.scan_parquet(path)).collect(engine="in-memory")
    elif mode == "streaming":
        res = q(pl.scan_parquet(path)).collect(engine="streaming")
    else:
        pl.scan_parquet(path).filter(pl.col("cat") == 3).with_columns((pl.col("v") * 2).alias("v2")) \\
          .sink_parquet(out)
        res = pl.scan_parquet(out).select(pl.len().alias("n"), pl.col("v").sum().alias("s")).collect()
    dt = time.perf_counter() - t0
    m = psutil.Process().memory_info()
    peak = getattr(m, "peak_wset", None) or __import__("resource").getrusage(0).ru_maxrss * 1024
    print(f"{dt:.3f} {peak / 2**20:.0f} {res.height} {int(res['n'].sum())} {round(float(res['s'].sum()), 1)}")
""")
print(f"{'query':14} {'engine / strategy':52} {'time':>8} {'peak RSS':>9}  rows out")
res = {}
for by, label, mode in [("key", "pl.read_parquet() + group_by (eager)", "eager"),
                        ("key", "scan_parquet()...collect(engine='in-memory')", "in-memory"),
                        ("key", "scan_parquet()...collect(engine='streaming')", "streaming"),
                        ("cat", "pl.read_parquet() + group_by (eager)", "eager"),
                        ("cat", "scan_parquet()...collect(engine='in-memory')", "in-memory"),
                        ("cat", "scan_parquet()...collect(engine='streaming')", "streaming"),
                        ("-", "scan_parquet().filter().sink_parquet()", "sink")]:
    out = os.path.join(tmp, f"out_{mode}.parquet")
    dt, peak, height, nrows, total = subprocess.run([sys.executable, "-c", CHILD, path, mode, out, by],
                                                    capture_output=True, text=True, check=True).stdout.split()
    res[(by, mode)] = (float(peak), int(nrows), float(total))
    q = {"key": "by key (3M)", "cat": "by cat (8)", "-": "filter+sink"}[by]
    print(f"  {q:12} {label:52} {float(dt) * 1e3:6.0f}ms {float(peak):7.0f}MiB  {int(height):>9,}")
    if os.path.exists(out):
        os.remove(out)
for by in ("key", "cat"):
    assert res[(by, "eager")][1:] == res[(by, "in-memory")][1:] == res[(by, "streaming")][1:]
assert res[("cat", "streaming")][0] < res[("cat", "eager")][0]
print(f"  results identical across engines for both queries ({res[('key', 'eager')][1]:,} rows aggregated)")
os.remove(path)
os.rmdir(tmp)
print("ALL ASSERTIONS PASSED")
```

Output (one measured run; each row its own process):

```text
Parquet: 30,000,000 rows, 414 MiB on disk, ~486 MiB decoded
query          engine / strategy                                        time  peak RSS  rows out
  by key (3M)  pl.read_parquet() + group_by (eager)                    801ms     968MiB  2,999,892
  by key (3M)  scan_parquet()...collect(engine='in-memory')            988ms    1451MiB  2,999,892
  by key (3M)  scan_parquet()...collect(engine='streaming')            809ms     947MiB  2,999,892
  by cat (8)   pl.read_parquet() + group_by (eager)                    176ms     731MiB          8
  by cat (8)   scan_parquet()...collect(engine='in-memory')            110ms     422MiB          8
  by cat (8)   scan_parquet()...collect(engine='streaming')            103ms     303MiB          8
  filter+sink  scan_parquet().filter().sink_parquet()                  209ms     561MiB          1
  results identical across engines for both queries (30,000,000 rows aggregated)
ALL ASSERTIONS PASSED
```

| Query shape | Eager peak | Streaming peak | Lesson |
|---|---:|---:|---|
| group by `cat` (8 keys), scan-dominated | 731 MiB | **303 MiB** | streaming bounds memory by morsels, not input |
| group by `key` (3 M keys), state-dominated | 968 MiB | 947 MiB | the hash table + result dominate; streaming can't help |
| filter + `sink_parquet` | — | ~560 MiB | output never materialized; peak = scan buffers × threads |

The in-memory engine on the lazy plan used *more* memory than eager here for the 3 M-key query (1.45 GiB): it scans the projected columns fully before aggregating in parallel. **Pattern:** for memory-bounded pipelines use `engine="streaming"` and `sink_*`, reduce cardinality early (pre-aggregate, filter, dictionary-encode keys), and cap threads in memory-tight pods, since peak scales with thread count × morsel size.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | OOM reading "just a few columns" | Eager `read_parquet` / `read_csv` then filter | No pushdown in the eager API | `scan_*` + lazy filters/selects, or `columns=` | Lint: `read_parquet` followed by `filter` |
| F2 ⚡ | Polars job no faster than pandas | One core busy; `PolarsInefficientMapWarning` | `map_elements`/`apply` UDFs serialize on the GIL | Native expressions; `map_batches`; Rust plugins | Treat the warning as an error in CI |
| F3 | Pushdown silently missing | `explain()` shows `FILTER` above the scan | Predicate uses a UDF or a non-pushable expression, or the filter sits after a row-count-changing op | Rewrite with native expressions; move filters earlier | Assert on `explain()` text in tests for key queries |
| F4 🔥 | Streaming job still OOMs | Peak tracks the number of distinct keys | Operator state (hash tables, sort runs) dominates | Pre-aggregate, reduce key cardinality, partition the input and run per partition | Model state size: keys × (key + accumulators) bytes |
| F5 | Pod throttled / noisy neighbours | Polars uses every core visible | Thread pool = detected cores, fixed at import | Set `POLARS_MAX_THREADS` to the pod's CPU limit **before** import | Container entrypoint sets it from the cgroup quota |
| F6 | Slow ingestion of string-heavy Arrow/Parquet | Time ∝ string bytes | Conversion to Utf8View | Produce `string_view` upstream, or accept the one-time cost | Know the engine's native layout (02.3) |
| F7 | Different results between eager and lazy code | Ordering differences | `group_by` doesn't keep order by default (`maintain_order=False`) | `maintain_order=True` or an explicit sort | Never rely on implicit ordering |
| F8 | Latency spikes from `collect()` on large plans | Re-planning each call | The query is rebuilt and optimized per request | Cache results; parametrize with filters on prepared LazyFrames; keep plans small | Benchmark planning time separately |

**Debugging toolkit.** `lf.explain()` / `lf.explain(optimized=False)` show plans, and `lf.show_graph()` draws them (Graphviz). `lf.profile()` gives per-node timings. `pl.thread_pool_size()` shows the pool. Set `POLARS_VERBOSE=1` for engine decisions and row-group pruning messages. Measure memory per strategy in a child process (Rust allocations are invisible to `tracemalloc`; 03.4).

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Walk through what `scan_parquet(...).filter(...).select(...).collect()` reads from disk."</b></summary>

**Initial Prompt.** A 12-column, 355 MiB Parquet file is queried for three columns over the last 10 % of the time range.

**L5 Answer.** "Polars reads the file and filters it fast in Rust."

**Why L5 Crashes at Scale.** If you believe the whole file is read, you size infrastructure for the file instead of the query, and you miss that pushdown depends on data *layout* (sorted or clustered columns, row-group size) as much as on the engine.

**L7 Principal Defense.** The optimizer rewrites the plan so the scan carries `PROJECT 3/12 COLUMNS` and `SELECTION: (amount > 50) & (ts >= c)`. The reader opens the footer, compares each row group's `ts` min/max with the predicate (only 2 of 20 qualify here), and decodes only those row groups and only the projected column chunks. Then `amount > 50` is evaluated on decoded pages. Measured: ~15–32 ms and ~85 MiB, against ~150–230 ms and ~680 MiB for eager. The layout lever is to write data clustered on the common filter keys (sorted `ts`), with row groups of 100 k–1 M rows, so statistics are selective. Random order gives every row group the full range and nothing can be skipped (03.3 shows this with DuckDB).

</details>

<details><summary><b>Q2 · "Polars is 'written in Rust', so it must beat pandas per core. True?"</b></summary>

**Initial Prompt.** A team assumes rewriting in Polars will give 10× on a 2-vCPU container.

**L5 Answer.** "Yes. Rust is faster than Python, so expect 10–50×."

**Why L5 Crashes at Scale.** pandas' hot paths are already C and Cython. Measured single-threaded, Polars was 0.9× pandas on a hash group-by. On a 2-vCPU pod, the parallelism that produced 3.7× on 12 threads isn't there. The rewrite pays off only where Polars changes the *algorithm*: pushdown, lazy fusion, streaming, avoiding Python UDFs.

**L7 Principal Defense.** Attribute speedups to mechanisms. I/O avoidance (projection and predicate pushdown) gives order-of-magnitude wins on wide or filtered scans regardless of cores. Parallelism scales with cores (4.2× from 1 → 12 threads here). Expression fusion and CSE avoid intermediate materialization (02.2). Python-UDF removal gives ~60× when the pandas code used `apply`. Benchmark the actual pipeline at the actual pod size, and set `POLARS_MAX_THREADS` to the CPU limit to avoid oversubscription.

</details>

<details><summary><b>Q3 · "Our streaming Polars job still OOMs. Isn't streaming supposed to be out-of-core?"</b></summary>

**Initial Prompt.** A `collect(engine="streaming")` group-by over a 500 GB dataset fails on a 64 GB node.

**L5 Answer.** "Streaming has bugs; use Spark."

**Why L5 Crashes at Scale.** Streaming bounds memory for data in flight, not for operator *state*. A group-by over billions of distinct keys needs a hash table proportional to the keys, plus the result. Spark would also need to spill or shuffle it; the problem is algorithmic, not the engine.

**L7 Principal Defense.** Model state: keys × (key bytes + accumulator bytes + hash overhead). Measured on a small scale: 8 keys streamed at 303 MiB against 731 MiB eager, while 3 M keys showed no benefit (947 vs 968 MiB). The fixes are structural. Partition the input by a hash of the key, process partitions sequentially (each fits), and `sink_parquet` per partition. Or pre-aggregate at a coarser grain first, or push the aggregation into a system that spills (DuckDB spills hash aggregates to disk under `memory_limit`, 03.3). If it's truly distributed scale, use Spark or Ray with a shuffle (Folder 04).

</details>

<details><summary><b>Q4 · "How do you put custom business logic into Polars without killing performance?"</b></summary>

**Initial Prompt.** A pricing rule needs a small Python function applied to every row of 100 M rows.

**L5 Answer.** "`pl.col("x").map_elements(my_fn)`."

**Why L5 Crashes at Scale.** `map_elements` calls Python once per value under the GIL: measured ~60× slower than the native expression, and serial whatever the thread pool size. At 100 M rows that's minutes of single-core work in an engine built to finish in seconds.

**L7 Principal Defense.** Use this ladder. (1) Express the rule with native expressions: `pl.when().then().otherwise()`, `replace`, joins against a rules table (vectorized, parallel, optimizable). (2) If it needs NumPy-level math, `map_batches` calls Python once per Series. (3) If it's a real kernel, compile it: a Numba ufunc via `map_batches`, or a Polars expression plugin in Rust (registered with `register_plugin_function`), which runs inside the engine without the GIL. (4) Keep Python UDFs only for tiny dimension tables. Treat `PolarsInefficientMapWarning` as a CI failure.

</details>

<details><summary><b>Q5 · "Why might the lazy in-memory engine use MORE memory than eager?"</b></summary>

**Initial Prompt.** A lazy group-by over Parquet peaked at 1.45 GiB while the eager version peaked at 0.97 GiB.

**L5 Answer.** "Lazy should always be better; it must be a measurement error."

**Why L5 Crashes at Scale.** It's a real effect, and assuming "lazy is always better" leads to wrong capacity decisions. The in-memory engine executes operator-at-a-time with full parallelism: it materializes the projected input columns, then builds per-thread partial hash tables before merging. With millions of keys, the partial tables multiply state.

**L7 Principal Defense.** Know the engine's memory model. In-memory means input columns plus per-thread state plus the result. Streaming means morsels × threads plus state. Eager means the whole input plus state. For high-cardinality aggregations, measure all three (the listing does) and choose by peak, not by habit. Reduce threads in memory-tight pods, pre-partition by key so each partition's state is small, and remember that predicate and projection pushdown help every engine.

</details>

<details><summary><b>Q6 · "How does Polars avoid the GIL, and what reintroduces it?"</b></summary>

**Initial Prompt.** Explain the concurrency model of a Polars query called from a FastAPI handler.

**L5 Answer.** "Polars is multithreaded, so it doesn't use the GIL."

**Why L5 Crashes at Scale.** Plan building and result handling *do* run Python. UDFs reacquire the GIL per call, and a `collect()` inside an async handler blocks the event loop for the whole query unless it's offloaded.

**L7 Principal Defense.** The Python thread builds the plan (cheap) and calls `collect()`, which runs in Rust on the pool with the GIL released. Other Python threads, including another request's handler, can run meanwhile. So in an asyncio server use `await asyncio.to_thread(lf.collect)`, or `collect(background=True)` / `collect_async()`, so the loop stays responsive: this is the GIL-releasing case where `to_thread` works (01.3). What reintroduces the GIL is `map_elements`/`map_batches` with Python functions and conversions to Python objects (`to_dicts`, `rows`). Keep those out of hot paths.

</details>

<details><summary><b>Q7 · "When would you choose Polars over DuckDB, and vice versa?"</b></summary>

**Initial Prompt.** Both are fast columnar engines in-process. Pick one for a feature pipeline and for analyst SQL.

**L5 Answer.** "They're equivalent; pick whichever the team likes."

**Why L5 Crashes at Scale.** They differ in API, optimizer strengths, out-of-core behaviour and ecosystem. Measured on this machine: Polars won rolling windows (34 vs 252 ms) and as-of joins (74 vs 417 ms), while DuckDB won a 20 M-row string group-by (02.3) and spills aggregates and sorts to disk under memory limits (03.3).

**L7 Principal Defense.** Use Polars for expression-heavy feature engineering in Python (windows, `over()`, as-of joins, list and struct columns), typed pipelines composed in code, and streaming sinks. Use DuckDB for SQL, large joins and aggregations that may exceed memory (robust spilling), ad-hoc analyst access over Parquet and Iceberg/Delta, and embedding in other services. Since both speak Arrow with zero copy (02.3), the best architecture often uses both, each step in the engine that does it best, with Arrow tables passed between them.

</details>

<details><summary><b>Q8 · "Design a nightly 2 TB Parquet → features job on a single 32-core, 128 GB node."</b></summary>

**Initial Prompt.** No cluster is available. The output is per-user features over 90 days of events.

**L5 Answer.** "Load it with pandas in chunks."

**Why L5 Crashes at Scale.** Chunked pandas can't do cross-chunk aggregations without hand-written merge logic. It's single-threaded and object-heavy, and it reads every column, so 2 TB of I/O plus Python per chunk is a 10+ hour job.

**L7 Principal Defense.** Lay out data for pushdown: partition by date, cluster by `user_id` within files, 100 k–1 M-row row groups. Use Polars lazy `scan_parquet` with projection to the needed columns and date-range predicates, so partitions and row groups are pruned. Hash-partition by `user_id` into N buckets (`partition_by` or one pass of `sink_parquet` per bucket), so each bucket's aggregation state fits in RAM. Then run the per-bucket feature query on the streaming engine with `POLARS_MAX_THREADS=32` and `sink_parquet` outputs. The heavy SQL-shaped joins against dimension tables can go to DuckDB with `memory_limit` and `temp_directory` on local NVMe. Validate with `explain()` assertions and per-bucket row counts.

</details>

---

## 5. Invariants Checklist

- [ ] Use `scan_*` + lazy queries for files. Eager `read_*` reads every column and row.
- [ ] Check `explain()`: `SELECTION:` and `PROJECT k/n COLUMNS` must appear *in the scan*.
- [ ] Row-group skipping needs clustered data and statistics; layout is part of the query.
- [ ] Polars' speed is parallelism + pushdown + no Python, not per-core magic (single-thread ≈ pandas here).
- [ ] `map_elements` = one GIL-holding Python call per value (~60× slower). Use native expressions, `map_batches` or plugins.
- [ ] Group independent expressions into one `with_columns`/`select`; they run in parallel.
- [ ] Streaming bounds data in flight, not operator state. Model hash-table size for high-cardinality group-bys.
- [ ] `POLARS_MAX_THREADS` is fixed at import. Set it from the container CPU limit.
- [ ] Measure Polars memory with RSS in a child process; `tracemalloc` can't see Rust allocations.

---

## 6. References

- Polars user guide, Lazy API — https://docs.pola.rs/user-guide/lazy/
- Polars user guide, Optimizations — https://docs.pola.rs/user-guide/lazy/optimizations/
- Polars user guide, Streaming — https://docs.pola.rs/user-guide/concepts/streaming/
- Polars user guide, Expression plugins — https://docs.pola.rs/user-guide/plugins/expr_plugins/
- Polars user guide, User-defined functions (`map_elements` vs `map_batches`) — https://docs.pola.rs/user-guide/expressions/user-defined-python-functions/
- Polars API, `LazyFrame.collect` (engines) — https://docs.pola.rs/api/python/stable/reference/lazyframe/api/polars.LazyFrame.collect.html
- Apache Parquet format (row groups, column chunks, statistics) — https://parquet.apache.org/docs/file-format/
- V. Leis et al., "Morsel-Driven Parallelism: A NUMA-Aware Query Evaluation Framework for the Many-Core Age", SIGMOD 2014, DOI 10.1145/2588555.2610507.
