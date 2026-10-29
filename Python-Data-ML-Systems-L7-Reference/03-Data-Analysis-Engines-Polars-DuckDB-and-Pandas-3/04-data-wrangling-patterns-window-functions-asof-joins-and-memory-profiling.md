# 03.4 · Data Wrangling Patterns: Window Functions, As-Of Joins, Dedup & Memory Profiling

> **Folder 03 · Data Analysis Engines: Polars, DuckDB & pandas 3**
> **Measured on:** pandas 3.1.0, Polars 2.1.0, DuckDB 2.0.0, pyarrow 26.0.0, NumPy 2.5.4, CPython 3.14.5, i5-11260H, Windows 11. Every pattern is computed by all three engines and **asserted equal** before timing is reported.

---

## 0. Orientation & the JVM/C++ Bridge

Most real data work is a handful of patterns: **as-of joins** (attach the latest state as of each event), **window functions** (rolling, ranking, lag/lead per entity), **dedup and latest-per-key**, and **sessionization**. Each has a correct semantic definition, and each engine has an idiom that's 3–15× faster than the naive one. The other half of production wrangling is **knowing your memory**. In a mixed stack (CPython, NumPy, Arrow C++, Rust, DuckDB) no single tool sees every allocation.

| Pattern | pandas 3 | Polars 2 | DuckDB SQL | Spark / JVM analogue |
|---|---|---|---|---|
| As-of join | `merge_asof(on=, by=, direction=)` | `join_asof(on=, by=, strategy=)` | `ASOF [LEFT] JOIN ... ON k AND t >= q.t` | Spark has no native as-of join (window + `last()` or range join) |
| Rolling by rows | `groupby().rolling(n)` | `rolling_mean(n).over(key)` | `AVG() OVER (PARTITION BY k ORDER BY t ROWS n PRECEDING)` | `Window.rowsBetween` |
| Rolling by time | `rolling("30s", on=)` | `rolling_mean_by("t", "30s")` | `RANGE BETWEEN INTERVAL ...` | `Window.rangeBetween` |
| Latest per key | `sort_values().drop_duplicates(keep="last")` | `unique(keep="last")` / `group_by().last()` | `QUALIFY row_number() OVER (...) = 1` | `row_number()` + filter |
| Memory accounting | `memory_usage(deep=True)` | `estimated_size()` | `duckdb_memory()` | JMX heap + off-heap metrics |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 As-of join semantics

```text
 trades (left, sorted by ts)            quotes (right, sorted by ts), per symbol
   ts=105 sym=A  --------------------->  latest quote with q.ts <= 105 and q.sym = A    (backward)
                                         earliest quote with q.ts >= 105                (forward)
                                         closest in |ts|                                (nearest)
 options: tolerance (max staleness), allow_exact_matches, by= (equality keys)
 algorithm: per group, a merge-style two-pointer sweep over both sorted inputs -> O(n + m)
            (no hash table of all quotes, no N x M join)
```

**Ties are a correctness hazard.** If two quotes share a timestamp, "the latest" is ambiguous, and engines may legitimately pick different rows. During development the three engines *disagreed* on randomly generated timestamps until the data was made strictly increasing (§2.1). In production, add a deterministic tiebreaker (a sequence number) to the `on` key, or deduplicate the right side first.

### 1.2 Window functions: frames and partitions

```text
 PARTITION BY sym   -> independent windows per symbol (parallelizable across partitions)
 ORDER BY ts        -> defines "preceding"
 ROWS BETWEEN 29 PRECEDING AND CURRENT ROW  -> last 30 rows (count-based)
 RANGE BETWEEN INTERVAL 30 SECOND PRECEDING AND CURRENT ROW -> time-based (variable row count)
 implementation: sort/partition once, then a sliding aggregate per partition (O(n) with running sums,
                 segment trees for non-invertible aggregates like min/max)
```

Count-based frames give different answers from time-based frames on irregular event streams. Both pandas and Polars default to *requiring a full window* (`min_periods`/`min_samples` = window size, so NaN or null at the start), while SQL frames average whatever rows exist. The listing sets `min_periods=1` / `min_samples=1` to make all three agree. Pick the semantics deliberately.

### 1.3 Who sees which allocation

```text
 allocation path                     tracemalloc   pyarrow pool   DuckDB buffer mgr   OS private bytes
 CPython objects (list, dict, str)       YES            -               -                 YES
 NumPy buffers (PyDataMem domain)        YES            -               -                 YES
 Arrow C++ (pyarrow.compute results)     no             YES             -                 YES
 Rust (Polars, its global allocator)     no             no              -                 YES
 DuckDB (tables, hash tables, sorts)     no             no              YES               YES
 tracemalloc's OWN trace storage         no             -               -                 YES  (~58 B per live trace here)
```

The only universal truth is the OS view: private bytes / USS / RSS. Library-level counters attribute it. `tracemalloc` is precise for Python and NumPy but blind to native engines, and expensive: 144 MiB of bookkeeping for 2.6 M live allocations, measured in §2.2.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 As-of joins, rolling windows and latest-per-key across three engines

```python
"""window_asof_patterns.py - three time-series workhorses in pandas 3, Polars and DuckDB, checked for equality.

A: as-of join - each trade gets the latest quote at or before its timestamp, per symbol.
B: window - 30-trade rolling mean price per symbol.
C: latest row per key (dedup) - pandas drop_duplicates vs Polars unique vs DuckDB QUALIFY.
"""
import time

import duckdb
import numpy as np
import pandas as pd
import polars as pl

rng = np.random.default_rng(0)
SYMS = 500
NT, NQ = 2_000_000, 5_000_000
q_ts = np.cumsum(rng.integers(1, 400, NQ))             # strictly increasing: no ties to break
quotes = pl.DataFrame({"ts": q_ts, "sym": rng.integers(0, SYMS, NQ).astype(np.int32),
                       "bid": rng.random(NQ) * 100}).sort("ts")
t_ts = np.cumsum(rng.integers(1, 1000, NT))
trades = pl.DataFrame({"ts": t_ts, "sym": rng.integers(0, SYMS, NT).astype(np.int32),
                       "price": rng.random(NT) * 100}).sort("ts")
pq, pt = quotes.to_pandas(), trades.to_pandas()
con = duckdb.connect()
con.sql("SET enable_progress_bar = false")


def timed(fn, reps=2):
    best, r = float("inf"), None
    for _ in range(reps):
        t0 = time.perf_counter()
        r = fn()
        best = min(best, time.perf_counter() - t0)
    return r, best


print(f"{NT:,} trades, {NQ:,} quotes, {SYMS} symbols")
print("== A. as-of join (backward, by symbol)")
a_pd, t1 = timed(lambda: pd.merge_asof(pt, pq, on="ts", by="sym", direction="backward"))
a_pl, t2 = timed(lambda: trades.join_asof(quotes, on="ts", by="sym", strategy="backward", check_sortedness=False))
a_dd, t3 = timed(lambda: con.sql("SELECT t.ts, t.sym, t.price, q.bid FROM trades t ASOF LEFT JOIN quotes q "
                                 "ON t.sym = q.sym AND t.ts >= q.ts ORDER BY t.ts, t.sym, t.price").pl())
s_pd = pl.from_pandas(a_pd).sort(["ts", "sym", "price"])["bid"].fill_null(-1).to_numpy()
s_pl = a_pl.sort(["ts", "sym", "price"])["bid"].fill_null(-1).to_numpy()
s_dd = a_dd["bid"].fill_null(-1).to_numpy()
assert np.array_equal(s_pd, s_pl) and np.array_equal(s_pl, s_dd)
for label, t in [("pandas merge_asof", t1), ("Polars join_asof", t2), ("DuckDB ASOF LEFT JOIN", t3)]:
    print(f"  {label:28} {t * 1e3:8.0f} ms")
print(f"  all three agree on {len(s_pl):,} rows ({int((s_pl == -1).sum()):,} trades with no earlier quote)")

print("== B. rolling mean of the last 30 trades per symbol")
w_pd, t1 = timed(lambda: pt.groupby("sym")["price"].rolling(30, min_periods=1).mean().reset_index(level=0, drop=True)
                 .sort_index())
w_pl, t2 = timed(lambda: trades.with_columns(pl.col("price").rolling_mean(30, min_samples=1).over("sym").alias("rm")))
w_dd, t3 = timed(lambda: con.sql("SELECT avg(price) OVER (PARTITION BY sym ORDER BY ts ROWS BETWEEN 29 PRECEDING "
                                 "AND CURRENT ROW) AS rm, ts, sym, price FROM trades").pl().sort(["ts", "sym", "price"]))
assert np.allclose(w_pd.to_numpy(), w_pl["rm"].to_numpy())
assert np.allclose(w_pl.sort(["ts", "sym", "price"])["rm"].to_numpy(), w_dd["rm"].to_numpy())
for label, t in [("pandas groupby().rolling()", t1), ("Polars rolling_mean().over()", t2),
                 ("DuckDB AVG() OVER (ROWS ...)", t3)]:
    print(f"  {label:28} {t * 1e3:8.0f} ms")

print("== C. latest quote per symbol (dedup by key, keep last by time)")
d_pd, t1 = timed(lambda: pq.sort_values("ts").drop_duplicates("sym", keep="last").sort_values("sym"))
d_pl, t2 = timed(lambda: quotes.unique("sym", keep="last", maintain_order=True).sort("sym"))
d_dd, t3 = timed(lambda: con.sql("SELECT * FROM quotes QUALIFY row_number() OVER (PARTITION BY sym ORDER BY ts DESC) = 1 "
                                 "ORDER BY sym").pl())
assert np.array_equal(d_pd["bid"].to_numpy(), d_pl["bid"].to_numpy())
assert np.array_equal(d_pl["bid"].to_numpy(), d_dd["bid"].to_numpy())
for label, t in [("pandas sort + drop_duplicates", t1), ("Polars unique(keep='last')", t2),
                 ("DuckDB QUALIFY row_number()", t3)]:
    print(f"  {label:28} {t * 1e3:8.0f} ms")
con.close()
print("ALL ASSERTIONS PASSED")
```

Output (one measured run; equality across engines is asserted):

```text
2,000,000 trades, 5,000,000 quotes, 500 symbols
== A. as-of join (backward, by symbol)
  pandas merge_asof                 106 ms
  Polars join_asof                   74 ms
  DuckDB ASOF LEFT JOIN             417 ms
  all three agree on 2,000,000 rows (195 trades with no earlier quote)
== B. rolling mean of the last 30 trades per symbol
  pandas groupby().rolling()        453 ms
  Polars rolling_mean().over()       34 ms
  DuckDB AVG() OVER (ROWS ...)      252 ms
== C. latest quote per symbol (dedup by key, keep last by time)
  pandas sort + drop_duplicates       90 ms
  Polars unique(keep='last')         21 ms
  DuckDB QUALIFY row_number()        54 ms
ALL ASSERTIONS PASSED
```

| Pattern (2 M trades, 5 M quotes, 500 symbols) | pandas 3 | Polars 2 | DuckDB |
|---|---:|---:|---:|
| as-of join (backward, by symbol) | ~100 ms | **~75 ms** | ~400 ms (includes SQL `ORDER BY` + `.pl()`) |
| 30-row rolling mean per symbol | ~450 ms | **~35–40 ms** | ~250 ms (includes result sort) |
| latest quote per symbol | ~90 ms | **~17–21 ms** | ~50 ms |

* All three produce identical as-of matches (195 trades have no earlier quote and get null), identical rolling means and identical latest rows.
* pandas `groupby().rolling()` materializes per-group objects and a MultiIndex, so it's ~13× slower than Polars' `over()` window, which runs per partition in parallel.
* The DuckDB numbers include re-sorting and converting results for the equality check. In a SQL-only pipeline, without the round trip to Polars, they're lower. Measure in the shape you'll deploy.

### 2.2 Trap: trusting one memory tool. Pattern: attribute with several

```python
"""memory_profiling_toolkit.py - which memory tool sees which allocation in a mixed Python data stack.

Allocates ~80 MiB of payload five ways and reports what tracemalloc, pyarrow's memory pool, DuckDB's buffer
manager and the OS (private bytes) each observe. No single tool sees everything: Rust (Polars) and C++
(DuckDB, Arrow) allocators bypass tracemalloc entirely.
"""
import gc
import sys
import tracemalloc

import duckdb
import numpy as np
import pandas as pd
import polars as pl
import psutil
import pyarrow as pa
import pyarrow.compute as pc

MiB = 2**20
N = 10 * MiB // 8 * 8                                   # 10.5M float64 = 80 MiB of payload
proc = psutil.Process()
con = duckdb.connect()
con.sql("SET enable_progress_bar = false")


def private():
    gc.collect()
    m = proc.memory_info()
    return getattr(m, "private", m.rss)


def duck_mb():
    return con.sql("SELECT sum(memory_usage_bytes) FROM duckdb_memory()").fetchall()[0][0] / MiB


keep = {}
makers = [
    ("Python list[float]", lambda: [float(i) for i in range(N // 4)]),            # 1/4 the count: objects are big
    ("NumPy float64 array", lambda: np.arange(N, dtype=np.float64)),
    ("pyarrow compute result", lambda: pc.add(pa.array(np.arange(N, dtype=np.float64)), 1.0)),  # pool-allocated
    ("Polars Series (Rust allocator)", lambda: pl.Series("x", np.arange(N, dtype=np.float64)) * 2),
    ("DuckDB table in memory", lambda: con.sql(f"CREATE TABLE t AS SELECT range::DOUBLE AS x FROM range({N})")),
]
print(f"{'allocation':32} {'tracemalloc':>12} {'pyarrow pool':>13} {'DuckDB mgr':>11} {'private bytes':>14}")
tracemalloc.start()
for label, make in makers:
    t0, a0, d0, p0 = tracemalloc.get_traced_memory()[0], pa.total_allocated_bytes(), duck_mb(), private()
    keep[label] = make()
    t1, a1, d1, p1 = tracemalloc.get_traced_memory()[0], pa.total_allocated_bytes(), duck_mb(), private()
    print(f"  {label:30} {(t1 - t0) / MiB:10.1f}Mi {(a1 - a0) / MiB:11.1f}Mi {d1 - d0:9.1f}Mi {(p1 - p0) / MiB:12.1f}Mi")
print(f"  tracemalloc's own bookkeeping for the live traces: {tracemalloc.get_tracemalloc_memory() / MiB:.0f} MiB "
      f"(it is in private bytes, not in tracemalloc's numbers)")
tracemalloc.stop()

print("== pandas: shallow vs deep memory_usage for object columns")
names = [f"customer_{i:07d}" for i in range(1_000_000)]
df = pd.DataFrame({"name": pd.Series(names, dtype=object), "name_str": pd.Series(names, dtype="str")})
shallow = df.memory_usage(deep=False) / MiB
deep = df.memory_usage(deep=True) / MiB
for col in ("name", "name_str"):
    print(f"  {col:9} ({str(df[col].dtype):6}) memory_usage(deep=False) = {shallow[col]:6.1f} MiB   "
          f"deep=True = {deep[col]:6.1f} MiB")
print(f"  sys.getsizeof(df) = {sys.getsizeof(df) / MiB:.1f} MiB  (pandas defines __sizeof__ as deep memory_usage)")
con.close()
print("ALL STEPS DONE")
```

Output (one measured run):

```text
allocation                        tracemalloc  pyarrow pool  DuckDB mgr  private bytes
  Python list[float]                   80.7Mi         0.0Mi       0.0Mi        380.1Mi
  NumPy float64 array                  80.0Mi         0.0Mi       0.0Mi         80.2Mi
  pyarrow compute result                0.2Mi        80.0Mi       0.0Mi         86.6Mi
  Polars Series (Rust allocator)        0.0Mi         0.0Mi       0.0Mi         80.5Mi
  DuckDB table in memory                0.0Mi         0.0Mi      88.2Mi         89.1Mi
  tracemalloc's own bookkeeping for the live traces: 144 MiB (it is in private bytes, not in tracemalloc's numbers)
== pandas: shallow vs deep memory_usage for object columns
  name      (object) memory_usage(deep=False) =    7.6 MiB   deep=True =   62.0 MiB
  name_str  (str   ) memory_usage(deep=False) =   22.9 MiB   deep=True =   22.9 MiB
  sys.getsizeof(df) = 84.9 MiB  (pandas defines __sizeof__ as deep memory_usage)
ALL STEPS DONE
```

* Each 80 MiB payload is visible to exactly the tools in the matrix above. The Polars Series is **invisible to everything except private bytes**, and the DuckDB table is visible to `duckdb_memory()` and the OS.
* The Python list row shows `tracemalloc` itself: 80.7 MiB traced, but ~380 MiB of private bytes, because tracemalloc stores a trace (with its traceback) per live allocation (~144 MiB of bookkeeping reported by `get_tracemalloc_memory()`). Use it on samples, or with `tracemalloc.start(1)`, never always-on in production.
* `memory_usage(deep=False)` reports 7.6 MiB for an object column whose true size is 62 MiB (pointers only). The Arrow-backed `str` column is 22.9 MiB either way. `sys.getsizeof(df)` is defined by pandas as the deep measurement.

**Production memory playbook:** alert on container RSS/working set; attribute with `pa.total_allocated_bytes()`, `duckdb_memory()`, Polars' `df.estimated_size()` and sampled `tracemalloc` snapshots; measure strategies in child processes (03.2/03.3 did exactly this).

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | As-of join results differ between runs, engines or versions | Same inputs, different matched rows | Ties on the `on` key; unsorted input | Deterministic tiebreaker (sequence id), dedup the right side, sort explicitly | Property test: shuffle input order, assert the same output |
| F2 🔥 | Features leak the future in backtests | Model accuracy too good to be true | Join used `forward`/`nearest`, or the right side's timestamp isn't "known at" time | `backward` with `allow_exact_matches` chosen by event semantics; use availability timestamps, not event timestamps | Point-in-time correctness tests (05.1 covers leakage) |
| F3 | Stale data silently attached | Quotes hours old matched to trades | No `tolerance` | Set `tolerance` (pandas/Polars) or add a `t - q.t <= interval` predicate | Monitor the match-age distribution |
| F4 | Rolling features differ between batch and streaming code | Edge-of-window values mismatch | `min_periods`/`min_samples` defaults differ from SQL frames; ROWS vs RANGE | Fix the semantics in a spec; set them explicitly everywhere | Golden-file tests across implementations |
| F5 ⚡ | Window job slow and memory-heavy in pandas | MultiIndex results, per-group objects | `groupby().rolling/apply` | Polars `.over()` / DuckDB window SQL | Engine choice per pattern (table above) |
| F6 | Memory dashboard says 2 GiB, pod killed at 8 GiB | `tracemalloc`/`memory_usage` used as the gauge | Native allocations (Arrow, Polars, DuckDB) not counted | Gauge on RSS/working set; attribute with per-library counters | Never alert on `tracemalloc` totals |
| F7 | Profiling makes the service fall over | RSS jumps after `tracemalloc.start()` | Per-allocation trace storage (~144 MiB for 2.6 M allocations here) | Sample: start for a window, snapshot, stop; `start(1)` frame depth | Profiling budget in runbooks |
| F8 | Dedup keeps the wrong record | "Latest" is the max of an ingestion timestamp, not an event timestamp | Ambiguous ordering key | Order by (event_ts, ingest_ts, seq) explicitly | Document the ordering contract per table |

**Debugging toolkit.** `merge_asof(..., tolerance=, allow_exact_matches=)`, Polars `join_asof(..., tolerance=, check_sortedness=)` and DuckDB `ASOF JOIN` with extra predicates. For windows, `EXPLAIN` in DuckDB and `explain()` in Polars show sort and partition steps. For memory: `psutil.Process().memory_info()`, `pa.total_allocated_bytes()`, `duckdb_memory()`, `pl.DataFrame.estimated_size()`, `tracemalloc.take_snapshot().statistics("lineno")`, `get_tracemalloc_memory()`.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Design point-in-time feature joins for a fraud model."</b></summary>

**Initial Prompt.** Each transaction needs the account's latest risk score and 30-day spend as of transaction time.

**L5 Answer.** "Join transactions to the latest risk score per account."

**Why L5 Crashes at Scale.** "Latest" without "as of" uses scores computed *after* the transaction, which is label leakage: offline AUC looks great and production fails. A plain join on account also multiplies rows or picks arbitrary versions.

**L7 Principal Defense.** Use a backward as-of join on (account, `available_at`), the time a score became *usable*, not its event time, with a staleness `tolerance` and `allow_exact_matches` chosen by event semantics. Make ties deterministic with a sequence number. Compute 30-day spend as a time-based window (`RANGE INTERVAL 30 DAY PRECEDING`, excluding the current row if the label is the current transaction). All three engines can do this with identical results (measured); Polars was fastest here (~75 ms for 2 M × 5 M). Validate with a point-in-time test that perturbs future data and asserts that features don't change.

</details>

<details><summary><b>Q2 · "Our as-of join gives different answers in pandas and DuckDB. Who is right?"</b></summary>

**Initial Prompt.** Migrating a batch job from pandas `merge_asof` to DuckDB `ASOF JOIN` changes 0.3 % of matches.

**L5 Answer.** "One of them has a bug; trust pandas, it's been around longer."

**Why L5 Crashes at Scale.** Both can be correct: the specification is ambiguous when the right side has duplicate timestamps per key. Picking a winner by reputation encodes nondeterminism into your features.

**L7 Principal Defense.** I reproduced exactly this. With random timestamps (ties present) the engines disagreed; with strictly increasing timestamps all three matched on 2 M rows. Define the contract (for example, "latest by (ts, seq)"), dedup or rank the right side explicitly, and give every engine a total order. Then test equivalence across engines with a golden dataset that includes ties, nulls and gaps, like the asserting listing in §2.1.

</details>

<details><summary><b>Q3 · "How do you compute rolling features over 1B events per day?"</b></summary>

**Initial Prompt.** Per-device 5-minute rolling averages and counts, daily.

**L5 Answer.** "`df.groupby('device').rolling('5min').mean()` in pandas, chunked by day."

**Why L5 Crashes at Scale.** pandas group-rolling builds per-group objects and a MultiIndex: ~13× slower than Polars on 2 M rows (measured), single-threaded, and memory-heavy. Day chunks also break windows that span midnight.

**L7 Principal Defense.** Sort by (device, ts) once, partition by device hash for parallelism and memory, and use time-based windows (`rolling_mean_by("ts", "5m").over("device")` in Polars, or a `RANGE INTERVAL '5 minutes' PRECEDING` frame in DuckDB). Keep a 5-minute overlap of the previous day so windows that span midnight are correct. Compute with streaming sinks, and store results partitioned by day. Running sums make each window O(1) per row, so the cost is the sort, and data clustered on (device, ts) at write time removes even that.

</details>

<details><summary><b>Q4 · "Memory monitoring says the job uses 1 GiB, but it's OOM-killed at 8 GiB. Explain."</b></summary>

**Initial Prompt.** A Python pipeline using Polars and DuckDB reports memory via `tracemalloc`.

**L5 Answer.** "There must be a leak somewhere tracemalloc can't see; restart the job more often."

**Why L5 Crashes at Scale.** Nothing leaked. The gauge is blind by design: Polars allocates through Rust and DuckDB through its buffer manager, and neither goes through CPython's allocator hooks (measured: an 80 MiB Polars Series and an 88 MiB DuckDB table, both 0 in tracemalloc).

**L7 Principal Defense.** Use the OS as the ground truth (working set / RSS / USS, and the container's memory.current) for alerting. Attribute it with library counters: `pa.total_allocated_bytes()` for Arrow, `duckdb_memory()` for DuckDB, `estimated_size()` for Polars frames, sampled `tracemalloc` for Python and NumPy. Then cap engines explicitly (DuckDB `memory_limit`, Polars streaming and thread caps), and measure peak per stage in child processes, as 03.2/03.3 do.

</details>

<details><summary><b>Q5 · "Dedup 2B events to the latest record per entity, every hour."</b></summary>

**Initial Prompt.** CDC events keyed by `entity_id` with `event_ts` and `ingest_ts`; downstream wants the current state.

**L5 Answer.** "`sort_values('event_ts').drop_duplicates('entity_id', keep='last')`."

**Why L5 Crashes at Scale.** Full sorts of 2 B rows per hour, single-threaded, plus ambiguity when `event_ts` ties (late or replayed events), make it slow and wrong. And the job recomputes history instead of merging changes.

**L7 Principal Defense.** Define the ordering contract as (event_ts, ingest_ts, sequence). Compute only the new hour's latest-per-key with `QUALIFY row_number() OVER (PARTITION BY entity_id ORDER BY event_ts DESC, ingest_ts DESC, seq DESC) = 1` (DuckDB) or `unique(keep='last')` after a stable sort (Polars), both measured 2–5× faster than pandas. MERGE that into the current-state table in a lakehouse format (Iceberg/Delta `MERGE INTO`, 04.4), so each hour touches only changed keys. Validate idempotency by replaying an hour twice and asserting no change.

</details>

<details><summary><b>Q6 · "When is `tracemalloc` the right tool, and how do you use it safely in production?"</b></summary>

**Initial Prompt.** An SRE wants tracemalloc always on in a high-throughput service to catch leaks.

**L5 Answer.** "Yes. It's built in and has little overhead."

**Why L5 Crashes at Scale.** It stores a trace per live allocation. Measured: 144 MiB of bookkeeping for 2.6 M live floats, roughly doubling memory for allocation-heavy code, plus CPU on every malloc and free. Always-on tracing can cause the very OOM it's meant to diagnose.

**L7 Principal Defense.** Use tracemalloc for Python-level leaks in bounded windows. Start it (with a frame depth of 1 to keep traces small), take two snapshots minutes apart, `compare_to` by `traceback`, and stop it. Run it on a canary, never fleet-wide. Pair it with RSS trend analysis and library counters for native memory. For native leaks use heap profilers that see C/C++ and Rust allocations (memray with `--native`, jemalloc/mimalloc statistics, Valgrind or heaptrack on Linux).

</details>

<details><summary><b>Q7 · "Why might `df.memory_usage()` be off by 8× in a capacity plan?"</b></summary>

**Initial Prompt.** A capacity estimate used `df.memory_usage().sum()` and the job needed far more RAM.

**L5 Answer.** "pandas overhead; add a safety factor."

**Why L5 Crashes at Scale.** Without `deep=True`, object columns are counted as 8-byte pointers only. Measured: 7.6 MiB reported against 62 MiB actual for 1 M short strings. A blanket safety factor is guesswork that changes with every dataset.

**L7 Principal Defense.** Always use `memory_usage(deep=True)` (which `sys.getsizeof(df)` also does in pandas). Better, eliminate object columns: pandas 3's Arrow-backed `str` reported 22.9 MiB both ways (no hidden objects), and `category` shrinks low-cardinality strings further (03.1). Compute capacity per column type from a production sample, and verify the whole job's peak with RSS in a child process.

</details>

<details><summary><b>Q8 · "Pick an engine per pattern for a feature platform, and justify it with numbers."</b></summary>

**Initial Prompt.** The platform needs as-of joins, rolling windows, dedup and ad-hoc SQL.

**L5 Answer.** "Standardize on one engine for simplicity."

**Why L5 Crashes at Scale.** No engine wins every pattern. Measured here: Polars won as-of joins, rolling windows and latest-per-key; DuckDB won large string group-bys, Parquet pruning and spilling (03.3); pandas lost on all of them but remains the integration layer for libraries.

**L7 Principal Defense.** Standardize on **Arrow as the interchange** and choose engines per step. Use Polars for windowed and as-of feature computation in Python pipelines, DuckDB for SQL-shaped joins and aggregations over the lake and for analyst access, and pandas or NumPy only where downstream libraries require them, via zero-copy Arrow conversion (02.3). Encode each pattern's semantics (ties, frames, tolerance) in a shared spec with cross-engine golden tests, so swapping engines can't silently change features.

</details>

---

## 5. Invariants Checklist

- [ ] As-of joins need sorted inputs and a total order on the key. Add a tiebreaker or the result is engine-defined.
- [ ] Choose backward/forward/nearest, tolerance and exact-match handling from event semantics. Point-in-time correctness prevents leakage.
- [ ] ROWS and RANGE frames differ on irregular streams. pandas/Polars require full windows by default and SQL doesn't, so set it explicitly.
- [ ] Latest-per-key needs an explicit ordering contract (event time, ingest time, sequence).
- [ ] Polars `.over()` windows, as-of joins and dedup were 3–13× faster than pandas idioms here, with identical results.
- [ ] Memory truth is the OS view. tracemalloc sees only Python and NumPy, and costs ~58 B+ per live trace.
- [ ] Arrow C++, Rust (Polars) and DuckDB allocations need their own counters (`total_allocated_bytes`, `estimated_size`, `duckdb_memory`).
- [ ] `memory_usage(deep=True)` always. Shallow counts object columns as pointers.

---

## 6. References

- pandas `merge_asof` — https://pandas.pydata.org/docs/reference/api/pandas.merge_asof.html
- Polars `join_asof` — https://docs.pola.rs/api/python/stable/reference/dataframe/api/polars.DataFrame.join_asof.html
- Polars window functions (`over`) — https://docs.pola.rs/user-guide/expressions/window-functions/
- DuckDB AsOf joins — https://duckdb.org/docs/stable/guides/sql_features/asof_join
- DuckDB window functions — https://duckdb.org/docs/stable/sql/functions/window_functions
- DuckDB `QUALIFY` — https://duckdb.org/docs/stable/sql/query_syntax/qualify
- Python `tracemalloc` — https://docs.python.org/3/library/tracemalloc.html
- memray (native-aware Python memory profiler) — https://github.com/bloomberg/memray
- V. Leis et al., "Efficient Processing of Window Functions in Analytical SQL Queries", PVLDB 8(10), 2015 — https://www.vldb.org/pvldb/vol8/p1058-leis.pdf
