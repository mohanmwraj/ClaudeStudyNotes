# 03.3 · DuckDB: In-Process OLAP, Vectorized Execution, Pushdown over Parquet & Arrow Integration

> **Folder 03 · Data Analysis Engines: Polars, DuckDB & pandas 3**
> **Measured on:** DuckDB 2.0.0 (Python client), pyarrow 26.0.0, Polars 2.1.0, pandas 3.1.0, CPython 3.14.5, i5-11260H (12 threads), 16 GB, Windows 11. Counters come from DuckDB's own `EXPLAIN ANALYZE`; peak memory from child processes.
> **Design sources:** DuckDB documentation (execution, Parquet reader, Hive partitioning, out-of-core, Python API), and DuckDB 2.0 API messages observed in these runs.

---

## 0. Orientation & the JVM/C++ Bridge

DuckDB is **"SQLite for analytics"**: a full columnar SQL engine linked into your process, with no server. It runs vectorized, push-based, morsel-parallel execution over its own storage or directly over Parquet, CSV, JSON, Arrow and DataFrames. For a backend architect it fills the gap between "pandas on one core" and "a Spark cluster": joins, aggregations, window functions and sorts larger than RAM on one node, in milliseconds to minutes, with predicates pushed into files.

| Concept | DuckDB | JVM analogue | C++ analogue |
|---|---|---|---|
| Deployment | in-process library (`import duckdb`) | embedded H2/Derby (row stores) | it *is* C++ |
| Execution | vectorized (2,048-value vectors), push-based pipelines, morsel parallelism | Spark Tungsten whole-stage codegen | Velox, ClickHouse |
| Storage | single-file DB; row groups of 122,880 rows; per-column zone maps | Parquet + Spark | — |
| File scans | Parquet/CSV/JSON readers with projection, predicate and Hive-partition pushdown | Spark DataSource V2 pushdown | Arrow Dataset |
| Out-of-core | hash aggregate, sort and join spill under `memory_limit` to `temp_directory` | Spark spill | — |
| Python bridge | replacement scans over DataFrames/Arrow; results as Arrow | Py4J + Arrow (04.1) | — |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 Vectorized, push-based, morsel-driven

```text
 SQL -> parser -> binder -> logical plan -> optimizer (filter/projection pushdown, join order,
        statistics propagation, expression rewriting) -> physical plan split into PIPELINES at
        pipeline breakers (hash table build, aggregate, sort)
 pipeline: Source -> Operator -> Operator -> Sink
   e.g.  READ_PARQUET -> FILTER -> PROJECTION -> HASH_GROUP_BY (sink)
 each worker thread repeatedly:
   take a morsel (a row-group range) from the source
   pull DataChunks of up to 2,048 rows (STANDARD_VECTOR_SIZE) through the operators
   (each column a Vector: flat / constant / dictionary / sequence encodings + validity mask)
   push into the sink's thread-local state; combine at the end
```

Why 2,048 rows? A chunk of a few columns fits in L1/L2, so each operator's tight loop over a vector stays in cache and amortizes interpretation overhead. That's the same physics as numexpr's blocks (02.2), applied to a whole query.

### 1.2 What a Parquet scan reads

```text
 read_parquet('events/*/*.parquet', hive_partitioning = true) WHERE day = 17 AND ts < c
   1. Hive partition pruning: directory names day=0..29 -> only day=17's file  ("File Filters: day = 17",
                                                                                 "Scanning Files: 1/30")
   2. footer: per row group, per column chunk: min/max/null_count statistics
      row group kept only if [min(ts), max(ts)] can satisfy ts < c          ("Row Groups Scanned: x / 4")
   3. projection: decode only column chunks referenced (amount, plus ts for the filter)
   4. remaining filters evaluated on decoded vectors
```

**Statistics only help if the data is clustered.** In this measurement DuckDB's default *parallel* `COPY ... PARTITION_BY` interleaved rows from several threads within each file: every row group spanned almost the whole day's `ts` range, and 2–4 of 4 row groups were scanned across runs. The same data written sorted with a single writer had disjoint ranges, and **1 of 4** row groups was scanned (1.2 MB read instead of 2.4–4.8 MB). The writer's parallelism silently destroyed the layout the reader depends on.

### 1.3 Memory management and spilling

```text
 memory_limit (default 80% of RAM: 12.5 GiB here)   managed by the buffer manager
   persistent data (DB file blocks) and temporary data (hash tables, sort runs) share the budget
   when an operator's state exceeds the budget -> partitions are written to temp_directory, processed later
   out-of-core operators: hash aggregate, ORDER BY, hash join, window
   temp_directory = '' disables spilling -> OutOfMemoryException instead
 threads (default = logical cores) -> parallelism AND memory (per-thread partial state)
```

### 1.4 The Python surface (DuckDB 2.0)

* **Replacement scans.** `duckdb.sql("SELECT ... FROM df")` resolves `df` from Python variables: pandas, Polars, Arrow tables, record batch readers, any `__arrow_c_stream__` producer. Arrow-native inputs are scanned in place (02.3).
* **Relations are lazy and re-run on every call.** DuckDB 2.0 removed `fetchone()` from relations with the message "a relation keeps no result between calls, so every call runs it again" (hit during development of §2.1). Materialize once (`to_arrow_table()`, `pl()`, `df()`) and reuse the result.
* **Results.** `to_arrow_table()` / `pl()` are columnar handoffs; `df()` converts to NumPy-backed pandas; `fetchall()` builds a Python tuple per row. `to_arrow_reader()` streams record batches. `fetch_arrow_table()`/`fetch_record_batch()` are deprecated in 2.0 (warnings observed).
* **UDFs.** `create_function(..., type="native")` calls Python per row; `type="arrow"` calls it per vector with Arrow arrays.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Trap: `pd.read_parquet` then filter. Pattern: query the files, and lay them out for pruning

```python
"""duckdb_pushdown_parquet.py - what DuckDB actually reads from a Hive-partitioned Parquet dataset.

Writes 12M rows partitioned by `day` (30 directories, 10 columns) twice: with the default parallel COPY and
with a sorted single-threaded COPY. EXPLAIN ANALYZE reports DuckDB's own counters (files scanned, row groups
scanned, bytes read). Partition filters prune files; min/max statistics prune row groups only if data is clustered.
"""
import os
import re
import shutil
import tempfile
import time

import duckdb
import pandas as pd

tmp = tempfile.mkdtemp()
par = os.path.join(tmp, "events_parallel").replace("\\", "/")
srt = os.path.join(tmp, "events_sorted").replace("\\", "/")
con = duckdb.connect()
con.sql("""CREATE TABLE src AS
           SELECT range AS ts, (range // 400000)::INT AS day, (hash(range) % 100000)::BIGINT AS user_id,
                  random() * 100 AS amount, random() AS f1, random() AS f2, random() AS f3,
                  random() AS f4, random() AS f5, random() AS f6
           FROM range(12000000)""")
con.sql(f"COPY src TO '{par}' (FORMAT parquet, PARTITION_BY (day), ROW_GROUP_SIZE 100000)")
con.sql("SET threads = 1")                             # one writer keeps rows in ORDER BY order inside each file
con.sql(f"COPY (SELECT * FROM src ORDER BY day, ts) TO '{srt}' (FORMAT parquet, PARTITION_BY (day), "
        "ROW_GROUP_SIZE 100000)")
con.sql("RESET threads")
files = sum(len(f) for _, _, f in os.walk(srt))
size = sum(os.path.getsize(os.path.join(r, x)) for r, _, fs in os.walk(srt) for x in fs) / 2**20
print(f"dataset: 12,000,000 rows, 10 columns, {files} files in 30 day=... partitions, {size:.0f} MiB (each layout)")
PAR = f"read_parquet('{par}/*/*.parquet', hive_partitioning = true)"
GLOB = f"read_parquet('{srt}/*/*.parquet', hive_partitioning = true)"
for name, path in [("parallel COPY", par), ("sorted, 1-thread COPY", srt)]:
    rg = con.sql(f"SELECT stats_min, stats_max FROM parquet_metadata('{path}/day=17/*.parquet') "
                 "WHERE path_in_schema = 'ts' ORDER BY row_group_id").fetchall()
    print(f"  ts min/max per row group in day=17 ({name:21}): {[(int(a), int(b)) for a, b in rg]}")


def profile(sql):
    plan = con.sql("EXPLAIN ANALYZE " + sql).fetchall()[0][1]
    get = lambda pat: (re.search(pat, plan) or [None, "-"])[1]
    return {"files": get(r"Scanning Files: (\d+/\d+)"), "row_groups": get(r"Row Groups Scanned: (\d+ / \d+)"),
            "read": get(r"Data Read:\s+([\d.]+ \w+)"), "time": float(get(r"Total Time: ([\d.]+)s"))}


queries = [
    ("partition filter: day = 17", f"SELECT sum(amount) FROM {GLOB} WHERE day = 17"),
    ("day=17 AND ts range, parallel layout", f"SELECT sum(amount) FROM {PAR} WHERE day = 17 AND ts < 6810000"),
    ("day=17 AND ts range, sorted layout", f"SELECT sum(amount) FROM {GLOB} WHERE day = 17 AND ts < 6810000"),
    ("unclustered filter: amount > 99.9", f"SELECT count(*) FROM {GLOB} WHERE amount > 99.9"),
    ("projection: 1 of 10 columns, no filter", f"SELECT sum(f1) FROM {GLOB}"),
    ("SELECT * (all columns) materialized", f"SELECT * FROM {GLOB} WHERE day = 17"),
]
print(f"{'query':40} {'files':>7} {'row groups':>11} {'data read':>10} {'time':>8}")
prof = {}
for label, sql in queries:
    p = prof[label] = profile(sql)
    print(f"  {label:38} {p['files']:>7} {p['row_groups']:>11} {p['read']:>10} {p['time'] * 1e3:6.1f}ms")
assert prof["day=17 AND ts range, sorted layout"]["row_groups"] == "1 / 4"
assert prof["partition filter: day = 17"]["files"] == "1/30"

print("== the same answer through pandas: read everything, then filter in Python land")
t0 = time.perf_counter()
pdf = pd.read_parquet(srt)                              # pyarrow dataset: all files, all columns
pd_sum = float(pdf.loc[pdf["day"] == 17, "amount"].sum())
t_pd = time.perf_counter() - t0
t0 = time.perf_counter()
dd_sum = con.sql(f"SELECT sum(amount) FROM {GLOB} WHERE day = 17").fetchall()[0][0]
t_dd = time.perf_counter() - t0
assert abs(pd_sum - dd_sum) < 1e-6 * abs(dd_sum)
print(f"  pandas read_parquet(all) + filter : {t_pd * 1e3:7.0f} ms, {pdf.memory_usage(deep=True).sum() / 2**20:.0f} MiB "
      f"materialized")
print(f"  DuckDB with pushdown              : {t_dd * 1e3:7.0f} ms")
del pdf
con.close()
shutil.rmtree(tmp)
print("ALL ASSERTIONS PASSED")
```

Output (one measured run; counters are DuckDB's own):

```text
dataset: 12,000,000 rows, 10 columns, 30 files in 30 day=... partitions, 738 MiB (each layout)
  ts min/max per row group in day=17 (parallel COPY        ): [(6881280, 7198719), (6800000, 7021183), (7021184, 7137919), (6804096, 7199999)]
  ts min/max per row group in day=17 (sorted, 1-thread COPY): [(6800000, 6900351), (6900352, 7000703), (7000704, 7101055), (7101056, 7199999)]
query                                      files  row groups  data read     time
  partition filter: day = 17                1/30       4 / 4     3.2 MB   13.1ms
  day=17 AND ts range, parallel layout      1/30       2 / 4     2.4 MB   17.3ms
  day=17 AND ts range, sorted layout        1/30       1 / 4     1.2 MB    8.1ms
  unclustered filter: amount > 99.9            -   120 / 120    96.9 MB   58.2ms
  projection: 1 of 10 columns, no filter       -   120 / 120    96.9 MB   38.5ms
  SELECT * (all columns) materialized       1/30       4 / 4    25.8 MB   20.1ms
== the same answer through pandas: read everything, then filter in Python land
  pandas read_parquet(all) + filter :     433 ms, 835 MiB materialized
  DuckDB with pushdown              :      15 ms
ALL ASSERTIONS PASSED
```

* Partition pruning read **1 of 30 files**: `sum(amount) WHERE day = 17` read ~3 MB of a 738 MiB dataset. Projection alone (a one-column sum over all files) read ~97 MB, one column's chunks.
* The `ts` range query shows the layout effect. On the parallel-written layout DuckDB scanned 2–4 of 4 row groups (varies by run, because the interleaving is nondeterministic); on the sorted layout it scanned **1 of 4** and read half as many bytes.
* A predicate on an unclustered column (`amount > 99.9`) can't prune: all 120 row groups, ~97 MB of that column.
* The pandas equivalent read everything (835 MiB materialized) in ~430 ms against ~15 ms. **Pattern:** keep data in Parquet with partitioning by the coarse filter key (date), *sort within files* by the next filter key, and let the engine read only what the query touches.

### 2.2 Threads, memory limits and spilling

```python
"""duckdb_spill_threads.py - DuckDB's morsel-parallel engine under thread and memory limits.

A 10M-row Parquet file is the input (so table storage doesn't count against the buffer pool). Each configuration
runs in a fresh child process: a high-cardinality GROUP BY and a full ORDER BY, both written back to Parquet.
With memory_limit below the working set, operators spill to temp_directory and finish; with spilling disabled
the same query raises OutOfMemoryException.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap

import duckdb

CHILD = textwrap.dedent("""
    import sys, time, psutil, duckdb
    threads, mem, tmpdir, src, out = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
    con = duckdb.connect(config={"threads": threads, "memory_limit": mem, "temp_directory": tmpdir})
    con.sql("SET enable_progress_bar = false")         # the bar writes to stdout during long queries
    status, t_group, t_sort = "ok", 0.0, 0.0
    try:
        t0 = time.perf_counter()
        con.sql(f"COPY (SELECT k, sum(v) AS s FROM read_parquet('{src}') GROUP BY k) TO '{out}_g.parquet'")
        t_group = time.perf_counter() - t0
        t0 = time.perf_counter()
        con.sql(f"COPY (SELECT * FROM read_parquet('{src}') ORDER BY v) TO '{out}_s.parquet'")
        t_sort = time.perf_counter() - t0
        groups = con.sql(f"SELECT count(*) FROM '{out}_g.parquet'").fetchall()[0][0]
    except duckdb.OutOfMemoryException:
        status, groups = "OutOfMemoryException", 0
    m = psutil.Process().memory_info()
    peak = getattr(m, "peak_wset", None) or __import__("resource").getrusage(0).ru_maxrss * 1024
    print(f"{t_group:.3f} {t_sort:.3f} {peak / 2**20:.0f} {groups} {status}")
""")

work = tempfile.mkdtemp()
src = os.path.join(work, "facts.parquet").replace("\\", "/")
con = duckdb.connect()
con.sql(f"""COPY (SELECT (hash(range) % 3000000)::BIGINT AS k, random() AS v FROM range(10000000))
            TO '{src}' (FORMAT parquet)""")
con.close()
print(f"input: 10,000,000 rows (k ~3M distinct, v double), {os.path.getsize(src) / 2**20:.0f} MiB Parquet")
print(f"{'threads':>8} {'memory_limit':>13} {'spill':>6} {'GROUP BY':>9} {'ORDER BY':>9} {'peak RSS':>9}  result")
res = {}
for threads, mem, spill in [(1, "8GB", True), (4, "8GB", True), (12, "8GB", True), (12, "150MB", True),
                            (12, "150MB", False)]:
    tmpdir = os.path.join(work, f"spill_{threads}_{mem}").replace("\\", "/") if spill else ""
    out = os.path.join(work, f"out_{threads}_{mem}_{spill}").replace("\\", "/")
    tg, ts, peak, groups, status = subprocess.run(
        [sys.executable, "-c", CHILD, str(threads), mem, tmpdir, src, out], capture_output=True, text=True,
        check=True).stdout.split()
    res[(threads, mem, spill)] = (float(tg), float(ts), float(peak), int(groups), status)
    shown = f"{int(groups):,} groups, sorted" if status == "ok" else status
    print(f"{threads:>8} {mem:>13} {('yes' if spill else 'no'):>6} {float(tg) * 1e3:7.0f}ms {float(ts) * 1e3:7.0f}ms "
          f"{float(peak):7.0f}MiB  {shown}")
spilled, full = res[(12, "150MB", True)], res[(12, "8GB", True)]
assert spilled[4] == "ok" and spilled[3] == full[3] and spilled[2] < full[2]
assert res[(12, "150MB", False)][4] == "OutOfMemoryException"
assert res[(1, "8GB", True)][0] > full[0]
shutil.rmtree(work, ignore_errors=True)
print("ALL ASSERTIONS PASSED")
```

Output (one measured run; each configuration in its own process):

```text
input: 10,000,000 rows (k ~3M distinct, v double), 124 MiB Parquet
 threads  memory_limit  spill  GROUP BY  ORDER BY  peak RSS  result
       1           8GB    yes     967ms    2419ms     419MiB  2,893,008 groups, sorted
       4           8GB    yes     338ms     824ms     506MiB  2,893,008 groups, sorted
      12           8GB    yes     398ms     607ms     568MiB  2,893,008 groups, sorted
      12         150MB    yes    1021ms    1027ms     255MiB  2,893,008 groups, sorted
      12         150MB     no       0ms       0ms     176MiB  OutOfMemoryException
ALL ASSERTIONS PASSED
```

* 1 → 12 threads: the GROUP BY gets ~2.5–3× faster and the sort ~4× faster, while **peak memory grows with threads** (419 → 570–610 MiB) because of per-thread partial state.
* At `memory_limit = 150MB` with a temp directory, both queries **complete with identical results at ~255 MiB peak** (Python and the DuckDB runtime included), spilling partitions to disk at roughly 1.7–2.6× the time.
* With spilling disabled the same query raises `OutOfMemoryException`. In containers, set `memory_limit` below the pod limit (leave room for Python and Arrow) and point `temp_directory` at fast local disk; otherwise the kernel's OOM killer arrives before DuckDB's own error.

### 2.3 Getting results out, and putting Python in

```python
"""duckdb_arrow_udf.py - getting results out of DuckDB, and putting Python logic into it.

A: materializing 5M result rows as Python tuples vs Arrow vs Polars vs pandas, and streaming record batches.
B: a Python UDF called per row (native) vs per vector (Arrow) vs the same logic in SQL.
"""
import time

import duckdb
import pyarrow as pa
import pyarrow.compute as pc

con = duckdb.connect()
con.sql("SET enable_progress_bar = false")
con.sql("CREATE TABLE t AS SELECT range AS id, random() * 100 AS amount, 'sku_' || (range % 5000) AS sku "
        "FROM range(5000000)")
Q = "SELECT * FROM t"


def timed(fn, reps=3):
    best, r = float("inf"), None
    for _ in range(reps):
        t0 = time.perf_counter()
        r = fn()
        best = min(best, time.perf_counter() - t0)
    return r, best


print(f"duckdb {duckdb.__version__}; 5,000,000 rows x (BIGINT, DOUBLE, VARCHAR)")
print("== A. result transfer to Python")
rows = [("fetchall() -> list of tuples", lambda: con.sql(Q).fetchall(), 1),
        (".to_arrow_table() -> pyarrow.Table", lambda: con.sql(Q).to_arrow_table(), 3),
        (".pl() -> polars.DataFrame", lambda: con.sql(Q).pl(), 3),
        (".df() -> pandas.DataFrame", lambda: con.sql(Q).df(), 3)]
base = None
for label, fn, reps in rows:
    r, dt = timed(fn, reps)
    n = len(r) if not hasattr(r, "num_rows") else r.num_rows
    base = base or dt
    print(f"  {label:38} {dt * 1e3:8.1f} ms  rows={n:,}  ({base / dt:5.1f}x vs fetchall)")
t0 = time.perf_counter()
reader = con.sql(Q).to_arrow_reader()
total, batches, biggest = 0.0, 0, 0
for batch in reader:                                    # bounded memory: one batch at a time
    total += pc.sum(batch.column("amount")).as_py()
    batches += 1
    biggest = max(biggest, batch.nbytes)
t_stream = time.perf_counter() - t0
print(f"  .to_arrow_reader() (streamed batches)  {t_stream * 1e3:8.1f} ms  batches={batches}, largest batch "
      f"{biggest / 2**20:.0f} MiB (vs whole table {con.sql(Q).to_arrow_table().nbytes / 2**20:.0f} MiB)")

print("== B. Python logic inside a query: price with 18% tax, rounded, on 5M rows")
con.create_function("tax_native", lambda x: round(x * 1.18, 2), ["DOUBLE"], "DOUBLE")
con.create_function("tax_arrow", lambda x: pc.round(pc.multiply(x, 1.18), 2), ["DOUBLE"], "DOUBLE", type="arrow")
variants = [("native Python UDF (one call per row)", "SELECT sum(tax_native(amount)) FROM t", 1),
            ("Arrow UDF (one call per 2048-row vector)", "SELECT sum(tax_arrow(amount)) FROM t", 3),
            ("pure SQL: round(amount * 1.18, 2)", "SELECT sum(round(amount * 1.18, 2)) FROM t", 3)]
out = {}
for label, sql, reps in variants:
    r, dt = timed(lambda: con.sql(sql).fetchall()[0][0], reps)
    out[label] = (r, dt)
    print(f"  {label:44} {dt * 1e3:8.1f} ms  sum={r:,.2f}")
vals = [v[0] for v in out.values()]
assert max(vals) - min(vals) < 1e-6 * abs(vals[0])
con.close()
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
duckdb 2.0.0; 5,000,000 rows x (BIGINT, DOUBLE, VARCHAR)
== A. result transfer to Python
  fetchall() -> list of tuples             2110.7 ms  rows=5,000,000  (  1.0x vs fetchall)
  .to_arrow_table() -> pyarrow.Table         25.8 ms  rows=5,000,000  ( 81.7x vs fetchall)
  .pl() -> polars.DataFrame                  43.6 ms  rows=5,000,000  ( 48.4x vs fetchall)
  .df() -> pandas.DataFrame                 568.3 ms  rows=5,000,000  (  3.7x vs fetchall)
  .to_arrow_reader() (streamed batches)      41.5 ms  batches=41, largest batch 3 MiB (vs whole table 134 MiB)
== B. Python logic inside a query: price with 18% tax, rounded, on 5M rows
  native Python UDF (one call per row)           2333.3 ms  sum=295,006,459.87
  Arrow UDF (one call per 2048-row vector)        357.8 ms  sum=295,006,459.87
  pure SQL: round(amount * 1.18, 2)                17.5 ms  sum=295,006,459.87
ALL ASSERTIONS PASSED
```

* `fetchall()` of 5 M rows takes ~2 s, because it builds a Python tuple and boxed values per row. `to_arrow_table()` takes ~26–33 ms (**60–80×**), `pl()` ~43 ms, and `df()` ~0.55 s (NumPy conversion and Python string handling for the VARCHAR column).
* `to_arrow_reader()` streams the result in ~3 MiB batches, so the consumer's memory is bounded no matter how large the result.
* Python logic inside SQL: a per-row native UDF takes ~2.3 s, an Arrow (per-vector) UDF ~360 ms, the same logic as SQL ~17 ms. Write business rules as SQL expressions or table joins; if Python is unavoidable, use `type="arrow"` with `pyarrow.compute` inside.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Pod OOM-killed running a big DuckDB join | Kernel OOM, no DuckDB error | `memory_limit` defaults to 80% of *host* RAM; the container limit is lower | `SET memory_limit` below the pod limit; `temp_directory` on local disk | Derive both from cgroup limits at startup |
| F2 | Query that should prune reads everything | `EXPLAIN ANALYZE` shows `Row Groups Scanned: N / N` | Data not clustered (parallel writes, random order) | Sort within files on filter keys; single-writer or per-partition sorted writes | Assert pruning counters in data-layout tests |
| F3 | `OutOfMemoryException` on large ORDER BY / GROUP BY | Error from DuckDB | Spilling disabled or temp disk full | Set `temp_directory`; ensure free disk ≥ working set | Monitor temp-directory usage |
| F4 ⚡ | Python service slow returning query results | Profile dominated by `fetchall`/`fetchone` loops | Per-row Python object creation | `to_arrow_table()`, `pl()`, `to_arrow_reader()` | Ban `fetchall` for large results |
| F5 | A query runs twice (or N times) per request | CPU doubled; same plan in the profile repeatedly | DuckDB 2.0 relations re-execute on each fetch/convert | Materialize once and reuse the Arrow/Polars result | Code review: relation reused across calls |
| F6 ⚡ | UDF-heavy query 100× slower than expected | Single core busy in Python | Native (per-row) Python UDF | SQL expressions; `type="arrow"` UDFs | Lint UDF registrations |
| F7 | Concurrent writers corrupt or block | Lock errors on the DB file | DuckDB is single-writer per database file (multiple readers OK) | One writer process; others read Parquet/attach read-only | Architect DuckDB as embedded, not as a multi-tenant OLTP server |
| F8 | Progress-bar text in logs or parsed stdout | Lines like `49%` in captured output | Interactive progress bar during long queries | `SET enable_progress_bar = false` (a session option, not a global config key) | Set it in service connection setup |

**Debugging toolkit.** `EXPLAIN` and `EXPLAIN ANALYZE` give operator trees with files and row groups scanned, data read and time. `PRAGMA enable_profiling='json'` gives machine-readable profiles. `FROM duckdb_memory()` shows buffer-manager usage by tag, `FROM duckdb_temporary_files()` shows spill files, and `FROM parquet_metadata('f.parquet')` / `parquet_schema()` show row-group statistics (as used in §2.1). `SET threads` and `SET memory_limit` control per-session behaviour.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why is DuckDB so fast in-process when it doesn't run on a cluster?"</b></summary>

**Initial Prompt.** Explain DuckDB's execution model to a team that only knows Spark.

**L5 Answer.** "It's written in C++ and uses columnar storage."

**Why L5 Crashes at Scale.** "C++ + columnar" doesn't predict which queries are fast, how memory scales with threads, or why a UDF ruins it. Teams without the execution model can't diagnose plans or design data layouts.

**L7 Principal Defense.** DuckDB compiles SQL into pipelines split at breakers. Each thread takes morsels (row-group ranges) and pushes 2,048-row vectors through cache-resident operators into thread-local sink state, then sinks merge. Inputs are pruned before decoding: Hive partitions (1/30 files measured), row-group min/max (1/4 with clustered data) and column projection. Memory is per-thread state under one buffer manager that can spill. So it's fast when work is pruned, vectorized and parallel, and slow when Python runs per row (UDFs ~130× slower than SQL measured) or results are materialized as Python objects (`fetchall` 60–80× slower than Arrow). Compared with Spark there's no serialization, no shuffle and no JVM: a single node's cores and memory bandwidth, used well.

</details>

<details><summary><b>Q2 · "Our partitioned Parquet lake prunes files but queries are still slow. Why?"</b></summary>

**Initial Prompt.** Queries filter by `day` and `ts`; `EXPLAIN` shows 1 file scanned, but all row groups inside it are read.

**L5 Answer.** "Add more partitions, e.g. by hour."

**Why L5 Crashes at Scale.** Over-partitioning creates millions of small files: metadata and listing overhead, poor compression, tiny row groups. The real issue is *intra-file* layout. Row-group statistics can't prune when each row group spans the whole range.

**L7 Principal Defense.** I measured it: a parallel `COPY ... PARTITION_BY` interleaved rows, so every row group spanned the full day and 2–4 of 4 were scanned. Writing sorted with one writer per partition gave disjoint ranges and 1 of 4 scanned, half the bytes. The fix keeps partitions coarse (day) and **sorts within files** by the secondary filter key (Z-order or Hilbert curves for several keys, which Delta and Iceberg compaction can do), with row groups of ~100 k–1 M rows. Verify with `parquet_metadata()` min/max per row group and `EXPLAIN ANALYZE` counters in a layout test, and run compaction jobs that rewrite small or unsorted files.

</details>

<details><summary><b>Q3 · "How do you run DuckDB safely inside a 4 GiB Kubernetes pod?"</b></summary>

**Initial Prompt.** A reporting service embeds DuckDB; heavy queries occasionally get the pod OOM-killed.

**L5 Answer.** "Increase the pod memory."

**Why L5 Crashes at Scale.** DuckDB's default `memory_limit` is 80 % of the *machine's* RAM as DuckDB sees it (12.5 GiB on this 16 GB laptop), not of the container limit. Without spill configuration a large aggregate grows until the kernel kills the process, taking every in-flight request with it.

**L7 Principal Defense.** Budget explicitly. Set `memory_limit` to ~60–70 % of the pod limit (leaving room for Python, Arrow results and the allocator) and `temp_directory` on a local SSD volume. Measured: at 150 MB the GROUP BY and ORDER BY still completed with identical results at ~255 MiB peak, slower but alive, while with spilling disabled the error is a catchable `OutOfMemoryException`, not a kill. Cap `threads` too, since peak memory grows with threads (419 → ~600 MiB, 1 → 12 threads). Stream results with `to_arrow_reader()` so result size doesn't add to the peak.

</details>

<details><summary><b>Q4 · "A query result of 5M rows takes 2 seconds to reach Python. Fix it."</b></summary>

**Initial Prompt.** The DuckDB query itself runs in 20 ms, but the endpoint takes 2+ s.

**L5 Answer.** "DuckDB is slow at returning data; cache the results."

**Why L5 Crashes at Scale.** The time is in `fetchall()`, building 5 M tuples and 15 M Python objects. Caching hides it until the cache misses, and multiplies memory with object overhead.

**L7 Principal Defense.** Return columnar data: `to_arrow_table()` (~26–33 ms measured, 60–80× faster) or `pl()`, and serialize with Arrow IPC or Parquet to the client, or with orjson over Arrow-derived columns only at the edge. For large results stream batches with `to_arrow_reader()`, keeping memory bounded at ~3 MiB per batch. And question the 5 M-row response: push the aggregation into SQL so only the needed rows cross into Python.

</details>

<details><summary><b>Q5 · "Can DuckDB replace our Spark cluster for nightly ETL?"</b></summary>

**Initial Prompt.** 1.5 TB of compressed Parquet per night, a few large joins, outputs back to the lake.

**L5 Answer.** "No. DuckDB is single-node, so it can't handle a terabyte."

**Why L5 Crashes at Scale.** Single-node doesn't mean small. With pushdown, most queries touch a fraction of the bytes, out-of-core operators handle state larger than RAM, and one 64–128 core node with NVMe can scan many GB/s. Dismissing it keeps paying for a cluster's shuffle and serialization overhead.

**L7 Principal Defense.** Decide by the shape of the work. Estimate bytes actually read after pruning, the size of join and aggregate state, and the deadline. If the hot join state fits in RAM plus spill on local NVMe, and scans are I/O-bound, a single DuckDB node is often cheaper and faster. Keep Spark or Ray (Folder 04) when data is truly distributed (multi-TB shuffles), when you need fault-tolerant retries of hours-long stages, or when concurrent multi-tenant jobs share a lakehouse. Many teams run DuckDB for the 80 % of jobs that fit and Spark for the rest, all over the same Iceberg/Delta tables (04.4).

</details>

<details><summary><b>Q6 · "Where should business logic live: SQL, Python UDFs, or DataFrame code?"</b></summary>

**Initial Prompt.** A pricing team wants to call their Python function from DuckDB SQL.

**L5 Answer.** "Register it with `create_function`. That's what it's for."

**Why L5 Crashes at Scale.** A native Python UDF runs per row under the GIL: measured ~2.3 s for 5 M rows against ~17 ms for equivalent SQL, more than 100×, serial, on the hottest query.

**L7 Principal Defense.** Prefer SQL expressions or rules tables joined in SQL (vectorized, parallel, optimizable). If Python is required, register it as an Arrow UDF (`type="arrow"`, ~360 ms measured) and write it with `pyarrow.compute` so each call processes a 2,048-row vector. For complex scoring, compute features in SQL, export via Arrow, and run the model in a vectorized ML runtime (ONNX Runtime, 05.3), not per row. Keep the rule's single source of truth in a tested module, shared by SQL generation and Python validation.

</details>

<details><summary><b>Q7 · "What are DuckDB's concurrency limits as an embedded database?"</b></summary>

**Initial Prompt.** A team proposes DuckDB as the backing store for a multi-user web app.

**L5 Answer.** "DuckDB is a database, so it handles concurrent users."

**Why L5 Crashes at Scale.** DuckDB is optimized for analytical reads and bulk writes with a single writer process per database file. Many concurrent small transactional writes (OLTP) contend on locks, and multiple processes can't write the same file concurrently.

**L7 Principal Defense.** Use DuckDB as an embedded analytical engine. One process writes (or each job writes its own files); many readers query Parquet or attach the DB read-only. Within one process, multiple threads and cursors can run queries concurrently. For multi-user transactional workloads keep Postgres (or similar), and point DuckDB at exported Parquet or attach Postgres for federated reads. For shared analytics across processes, store data as Parquet/Iceberg in object storage so every reader is independent.

</details>

<details><summary><b>Q8 · "How do Arrow and DuckDB work together in a Python pipeline?"</b></summary>

**Initial Prompt.** Data arrives as Polars frames, is joined in DuckDB, and is returned to Polars for feature work.

**L5 Answer.** "Convert Polars to pandas, register it, query it, convert back."

**Why L5 Crashes at Scale.** Every pandas detour copies numerics into NumPy and may create object strings (02.3), and converting results with `df()` costs ~0.55 s per 5 M rows against ~43 ms for `pl()`.

**L7 Principal Defense.** Use replacement scans directly on the Polars frame: DuckDB pulls Arrow batches through `__arrow_c_stream__`, reading Polars' buffers in place (02.3). Run the join in DuckDB, then return `.pl()` or `to_arrow_table()`, columnar and zero-copy for numerics. Keep the Arrow schema stable across the boundary (types, dictionary encoding, string views), and test the round trip with buffer-address assertions for the large columns.

</details>

---

## 5. Invariants Checklist

- [ ] DuckDB executes 2,048-row vectors through push-based pipelines, one morsel per thread at a time.
- [ ] File scans prune Hive partitions, row groups (min/max) and columns. Verify with `EXPLAIN ANALYZE` counters.
- [ ] Row-group pruning requires clustered data. Parallel writers can interleave rows: sort within files.
- [ ] Set `memory_limit` below the container limit and `temp_directory` on local disk. Spilling turns OOM into slower success.
- [ ] Peak memory grows with threads (per-thread state). Cap both in pods.
- [ ] Return results as Arrow/Polars (60–80× faster than `fetchall`), and stream with `to_arrow_reader()`.
- [ ] DuckDB 2.0 relations re-execute per call. Materialize once.
- [ ] Python UDFs per row are >100× slower than SQL. Use SQL or Arrow UDFs.
- [ ] One writer per database file. DuckDB is an embedded OLAP engine, not an OLTP server.

---

## 6. References

- DuckDB documentation — https://duckdb.org/docs/stable/
- DuckDB Parquet reading (filter/projection pushdown) — https://duckdb.org/docs/stable/data/parquet/overview
- DuckDB Hive partitioning — https://duckdb.org/docs/stable/data/partitioning/hive_partitioning
- DuckDB `EXPLAIN ANALYZE` / profiling — https://duckdb.org/docs/stable/dev/profiling
- DuckDB memory management and spilling ("larger-than-memory workloads") — https://duckdb.org/docs/stable/guides/performance/how_to_tune_workloads
- DuckDB Python API (relations, results, UDFs) — https://duckdb.org/docs/stable/clients/python/overview
- DuckDB Python function API (`create_function`) — https://duckdb.org/docs/stable/clients/python/function
- DuckDB concurrency — https://duckdb.org/docs/stable/connect/concurrency
- M. Raasveldt, H. Mühleisen, "DuckDB: an Embeddable Analytical Database", SIGMOD 2019 (demo), DOI 10.1145/3299869.3320212.
- P. Boncz, M. Zukowski, N. Nes, "MonetDB/X100: Hyper-Pipelining Query Execution", CIDR 2005 (vectorized execution) — https://www.cidrdb.org/cidr2005/papers/P19.pdf
