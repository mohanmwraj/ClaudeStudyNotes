# 03.1 · pandas 3 Internals: PyArrow Backend, Mandatory Copy-on-Write & Index Pitfalls

> **Folder 03 · Data Analysis Engines: Polars, DuckDB & pandas 3**
> **Measured on:** pandas 3.1.0, pyarrow 26.0.0, NumPy 2.5.4, CPython 3.14.5, i5-11260H (6C/12T), 16 GB, Windows 11.
> **Design sources:** PDEP-7 (Copy-on-Write), PDEP-14 (dedicated string dtype), the pandas 3.0 release notes, and `pandas.core.internals` (`BlockManager`, blocks) as observed through `df._mgr`.

---

## 0. Orientation & the JVM/C++ Bridge

pandas is a **labelled, column-oriented container on top of NumPy (and now Arrow) buffers**, plus an index that acts as an implicit join key on every operation. Its historical costs (copies everywhere, object-dtype strings, row-wise idioms) drove the "you need 5–10× your dataset's size in RAM" rule. pandas 3 changed two defaults to attack them: **Copy-on-Write is mandatory**, and **strings default to a PyArrow-backed `str` dtype**. What it didn't change is that pandas is eager and mostly single-threaded, with the index semantics on top. That's why Polars and DuckDB (03.2, 03.3) win production ETL, and why pandas remains the lingua franca at the edges.

| Concept | pandas 3 | JVM analogue | C++ analogue |
|---|---|---|---|
| Table | `DataFrame` = `BlockManager` of 2-D blocks + axes | Spark `Dataset` (but local and eager) | a struct of `std::vector`s |
| Column storage | NumPy 2-D blocks per dtype, or 1-D ExtensionArrays (Arrow) | `double[]` per column | `std::vector<double>` |
| Strings | `str` dtype backed by Arrow (`ArrowStringArray`) | `String[]` (objects) | `std::vector<std::string>` / string pool |
| Copy semantics | Copy-on-Write: lazy copies, copy on first write | immutable collections / persistent data structures | `shared_ptr` + clone-on-write (COW `std::string` pre-C++11) |
| Index | hash engine (khash) or sorted engine; aligns operands | `HashMap<label, position>` | `std::unordered_map` |
| Row loop | `iterrows`/`apply(axis=1)`: a Series per row | `forEach` over boxed rows | — |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 The BlockManager

```text
 DataFrame
  |- axes: [columns Index, row Index]
  `- _mgr: BlockManager
        blocks: (consolidated by dtype; NumPy blocks are 2-D, shape = (n_columns_in_block, n_rows))
          Block(float64)  values: ndarray (3, n)   mgr_locs -> columns [f1, f2, f3]
          Block(int64)    values: ndarray (1, n)   mgr_locs -> [i1]
          ExtensionBlock(str) values: ArrowStringArray (1-D)  mgr_locs -> [s]
 df["f2"]   -> a 1-D view of row 1 of the float64 block (contiguous: blocks are stored column-major per column)
 df.iloc[i] -> gathers one element from every block -> a new Series of a common dtype (slow, often object)
```

Consequences, measured in §2:

* **Column access is cheap, row access is expensive.** Each column is a contiguous 1-D slice of its block, and a row touches every block.
* **Consolidation.** Same-dtype columns merge into one 2-D block. Inserting columns one at a time creates one block per insert: 300 blocks, a `PerformanceWarning: DataFrame is highly fragmented` beyond 100, and row-wise reductions ~4× slower until something consolidates it.
* **Extension arrays (Arrow strings, `ArrowDtype`, `category`, nullable `Int64`) are 1-D blocks** and never consolidate. That's fine for column work and irrelevant to the old 2-D layout tricks.

### 1.2 Copy-on-Write (PDEP-7), mandatory in pandas 3

```text
 df2 = df["a"]            -> new Series object whose values VIEW df's block; both register a reference
                             in a shared refs tracker (weakrefs)
 df2.iloc[0] = 99         -> write path checks "is my buffer referenced by someone else?"
                             yes -> copy the affected values first (only the written column), then write
 df["b"][1] = -1          -> df["b"] is a temporary; the write lands in a copy that is discarded
                             -> ChainedAssignmentError warning, df unchanged (measured)
 df.loc[1, "b"] = -1      -> a single indexing call on df itself: the only correct way
```

Every method that used to copy defensively (`rename`, `reset_index`, `set_axis`, `astype` to the same dtype, `drop`, `select_dtypes`…) now returns a **lazy copy**. A five-step method chain costs ~0 bytes until something writes, and then only the written column is copied (measured: 15.3 MiB, not the 153 MiB frame). `pd.options.mode.copy_on_write` is deprecated and has no effect.

### 1.3 Strings: `object` vs `str` (PDEP-14)

```text
 object dtype (pandas <= 2 default)          str dtype (pandas 3 default, PyArrow installed)
 ndarray[object] of PyObject* (8 B each)     ArrowStringArray -> Arrow utf8/large_utf8: validity + offsets + bytes
   -> one PyUnicode object per value           -> 1 contiguous byte buffer, no per-value objects
      (~50-60 B header + chars)                -> vectorized kernels (pyarrow.compute) for .str methods
 missing value: None or NaN, mixed           missing value: NaN (na_value=np.nan semantics, PDEP-14)
```

The `str` dtype is what makes pandas 3 interoperate with Arrow engines without copying strings (02.3 measured buffer reuse). It's also where most of pandas 3's memory win comes from: 3.4× → 1.4× the CSV size for this dataset.

### 1.4 The index is a join key

Binary operations **align on labels** before computing: `a + b` is an outer join on the index, then elementwise. Assigning a Series to a column aligns too, which is right when it's what you meant and a silent bug when you expected positional assignment. Lookups use an index engine: a hash table (khash) for unique indexes, binary search for monotonic ones, and a scan or mask for non-unique ones. A single duplicate label switches the whole index to the slow path and changes `.loc`'s *return type* from scalar to Series.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Copy-on-Write and the BlockManager, observed

```python
"""pandas3_cow_blocks.py - pandas 3 Copy-on-Write and the BlockManager underneath every DataFrame.

A: CoW - derived objects share memory until one side writes; chained assignment never writes through.
B: method chains cost ~0 bytes until the first write, which pays for a full block copy.
C: the BlockManager - same-dtype columns live in 2-D blocks; inserting columns one by one fragments it.
"""
import time
import tracemalloc
import warnings

import numpy as np
import pandas as pd

print(f"pandas {pd.__version__}")
print("== A. Copy-on-Write semantics")
df = pd.DataFrame({"a": np.arange(5.0), "b": np.arange(5.0) * 10})
s = df["a"]
print(f"  s = df['a'] shares memory with df: {np.shares_memory(s.to_numpy(), df['a'].to_numpy())}")
s.iloc[0] = 99.0                                       # first write to s: s gets its own copy
print(f"  after s.iloc[0] = 99: df.a[0] = {df['a'].iloc[0]}, s[0] = {s.iloc[0]}, "
      f"shares memory: {np.shares_memory(s.to_numpy(), df['a'].to_numpy())}")
with warnings.catch_warnings(record=True) as w:
    warnings.simplefilter("always")
    df["b"][1] = -1.0                                  # chained assignment: writes to a temporary
print(f"  df['b'][1] = -1 -> df.b[1] = {df['b'].iloc[1]} ; warning: {w[0].category.__name__}")
df.loc[1, "b"] = -1.0                                  # the one correct way: a single indexing call
print(f"  df.loc[1, 'b'] = -1 -> df.b[1] = {df['b'].iloc[1]}")
assert df["a"].iloc[0] == 0.0 and df["b"].iloc[1] == -1.0

print("== B. a method chain on a 2M x 10 float64 frame (153 MiB): who pays, and when")
big = pd.DataFrame(np.random.default_rng(0).random((2_000_000, 10)), columns=[f"c{i}" for i in range(10)])


def measured(fn):
    tracemalloc.start()
    t0 = time.perf_counter()
    r = fn()
    dt = time.perf_counter() - t0
    cur, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    return r, peak / 2**20, dt


chain, mb, dt = measured(lambda: big.rename(columns=str.upper).reset_index(drop=True).set_axis(big.columns, axis=1))
print(f"  rename -> reset_index -> set_axis : peak {mb:7.1f} MiB  {dt * 1e3:6.1f} ms  (lazy copies only)")
_, mb, dt = measured(lambda: chain.iloc.__setitem__((0, 0), -1.0))
print(f"  first write chain.iloc[0, 0] = -1: peak {mb:7.1f} MiB  {dt * 1e3:6.1f} ms  (the block is copied now)")
print(f"  big untouched: big.iloc[0, 0] = {big.iloc[0, 0]:.4f}")
_, mb, dt = measured(lambda: big.copy())
print(f"  explicit big.copy()               : peak {mb:7.1f} MiB  {dt * 1e3:6.1f} ms")

print("== C. the BlockManager: columns grouped by dtype into 2-D blocks")
mixed = pd.DataFrame({"f1": np.ones(4), "f2": np.ones(4), "i1": np.arange(4), "s": ["w", "x", "y", "z"],
                      "f3": np.zeros(4)})
for blk in mixed._mgr.blocks:
    print(f"  block dtype={str(blk.dtype):8} shape={blk.shape} (n_columns, n_rows)  columns="
          f"{list(mixed.columns[blk.mgr_locs.as_array])}")
n, cols = 200_000, 300
base = np.random.default_rng(1).random(n)
t0 = time.perf_counter()
with warnings.catch_warnings(record=True) as w:
    warnings.simplefilter("always")
    frag = pd.DataFrame(index=range(n))
    for i in range(cols):
        frag[f"c{i}"] = base                           # one new block per insert
t_insert = time.perf_counter() - t0
perf_warnings = sum(1 for x in w if issubclass(x.category, pd.errors.PerformanceWarning))
t0 = time.perf_counter()
whole = pd.DataFrame({f"c{i}": base for i in range(cols)})   # consolidated at construction
t_dict = time.perf_counter() - t0
print(f"  insert {cols} columns one at a time: {t_insert * 1e3:7.1f} ms, nblocks={frag._mgr.nblocks}, "
      f"PerformanceWarnings={perf_warnings}")
print(f"  build from a dict of columns      : {t_dict * 1e3:7.1f} ms, nblocks={whole._mgr.nblocks}")
for label, d in [("fragmented", frag), ("consolidated", whole)]:
    t0 = time.perf_counter()
    d.sum(axis=1)
    print(f"  {label:13} df.sum(axis=1): {(time.perf_counter() - t0) * 1e3:7.1f} ms")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
pandas 3.1.0
== A. Copy-on-Write semantics
  s = df['a'] shares memory with df: True
  after s.iloc[0] = 99: df.a[0] = 0.0, s[0] = 99.0, shares memory: False
  df['b'][1] = -1 -> df.b[1] = 10.0 ; warning: ChainedAssignmentError
  df.loc[1, 'b'] = -1 -> df.b[1] = -1.0
== B. a method chain on a 2M x 10 float64 frame (153 MiB): who pays, and when
  rename -> reset_index -> set_axis : peak     0.0 MiB     1.2 ms  (lazy copies only)
  first write chain.iloc[0, 0] = -1: peak    15.3 MiB     3.2 ms  (the block is copied now)
  big untouched: big.iloc[0, 0] = 0.6370
  explicit big.copy()               : peak   152.6 MiB    23.0 ms
== C. the BlockManager: columns grouped by dtype into 2-D blocks
  block dtype=float64  shape=(3, 4) (n_columns, n_rows)  columns=['f1', 'f2', 'f3']
  block dtype=int64    shape=(1, 4) (n_columns, n_rows)  columns=['i1']
  block dtype=str      shape=(1, 4) (n_columns, n_rows)  columns=['s']
  insert 300 columns one at a time:   147.4 ms, nblocks=300, PerformanceWarnings=200
  build from a dict of columns      :    59.9 ms, nblocks=1
  fragmented    df.sum(axis=1):   283.2 ms
  consolidated  df.sum(axis=1):    69.5 ms
ALL ASSERTIONS PASSED
```

* **A:** derived Series share memory until written. Chained assignment no longer writes through and warns `ChainedAssignmentError`. The fix is a single `.loc`/`.iloc` call on the frame you mean to change.
* **B:** a three-step chain costs **0 MiB and ~1 ms**. The first write copies **one column (15.3 MiB)**, not the frame (an explicit `.copy()` is 153 MiB). Under CoW, idiomatic method chains are *cheaper* than the in-place mutation style pandas users were taught.
* **C:** block layout and fragmentation. 300 single-column inserts produce 300 blocks and 200 `PerformanceWarning`s, and `sum(axis=1)` runs ~4× slower than on a frame built in one go. **Pattern:** build columns in a dict and construct once (or `pd.concat(axis=1)` once), never `df[c] = ...` in a loop.

### 2.2 Trap: object strings and the 5–10× rule

```python
"""pandas3_strings_memory.py - why legacy pandas needed 5-10x the CSV size in RAM, and what pandas 3 changed.

Writes a 2M-row CSV, reads it back with object strings (the pandas <= 2 default), pandas 3's default `str`
(PyArrow-backed), and category; compares bytes in RAM per byte on disk, read time and string-op speed.
"""
import os
import tempfile
import time

import numpy as np
import pandas as pd
import pyarrow as pa

N = 2_000_000
rng = np.random.default_rng(0)
cities = np.array([f"city_{i:03d}" for i in range(100)])
src = pd.DataFrame({"id": np.arange(N), "city": cities[rng.integers(0, 100, N)],
                    "name": [f"customer_{i:07d}_{'abcdefgh'[i % 8]}" for i in rng.integers(0, 10**7, N)],
                    "amount": rng.random(N).round(2)})
tmp = tempfile.mkdtemp()
path = os.path.join(tmp, "orders.csv")
src.to_csv(path, index=False)
csv_mb = os.path.getsize(path) / 2**20
print(f"pandas {pd.__version__}, pyarrow {pa.__version__}; CSV {N:,} rows = {csv_mb:.1f} MiB on disk")


def timed(fn):
    t0 = time.perf_counter()
    r = fn()
    return r, time.perf_counter() - t0


variants = {
    "object strings (pandas <= 2 default)": lambda: pd.read_csv(path, dtype={"city": object, "name": object}),
    "pandas 3 default (str, PyArrow)": lambda: pd.read_csv(path),
    "engine='pyarrow' (multithreaded parser)": lambda: pd.read_csv(path, engine="pyarrow"),
    "str + city as category": lambda: pd.read_csv(path, dtype={"city": "category"}),
}
frames = {}
print(f"{'read variant':42} {'read':>8} {'RAM (deep)':>11} {'RAM/CSV':>8}  dtypes(city, name)")
for label, fn in variants.items():
    d, dt = timed(fn)
    mb = d.memory_usage(deep=True).sum() / 2**20
    frames[label] = d
    print(f"  {label:40} {dt * 1e3:6.0f}ms {mb:9.1f}MiB {mb / csv_mb:7.2f}x  {d['city'].dtype}, {d['name'].dtype}")
obj, s3, cat = (frames[k] for k in ("object strings (pandas <= 2 default)", "pandas 3 default (str, PyArrow)",
                                    "str + city as category"))
assert (obj["name"] == s3["name"]).all()

print("== string operations (ms)")
print(f"  {'operation':38} {'object':>9} {'str (arrow)':>12} {'category':>9}")
ops = [("name.str.contains('_a')", lambda d: d["name"].str.contains("_a", regex=False).sum()),
       ("name.str.len().mean()", lambda d: d["name"].str.len().mean()),
       ("city == 'city_042'", lambda d: (d["city"] == "city_042").sum()),
       ("groupby(city).amount.sum()", lambda d: d.groupby("city", observed=True)["amount"].sum())]
for label, fn in ops:
    r_obj, t_obj = timed(lambda: fn(obj))
    r_s3, t_s3 = timed(lambda: fn(s3))
    r_cat, t_cat = timed(lambda: fn(cat))
    if not isinstance(r_obj, pd.Series):
        assert r_obj == r_s3 == r_cat or abs(r_obj - r_s3) < 1e-9
    print(f"  {label:38} {t_obj * 1e3:9.1f} {t_s3 * 1e3:12.1f} {t_cat * 1e3:9.1f}")
os.remove(path)
os.rmdir(tmp)
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
pandas 3.1.0, pyarrow 26.0.0; CSV 2,000,000 rows = 78.9 MiB on disk
read variant                                   read  RAM (deep)  RAM/CSV  dtypes(city, name)
  object strings (pandas <= 2 default)        485ms     267.0MiB    3.39x  object, object
  pandas 3 default (str, PyArrow)              57ms     110.6MiB    1.40x  str, str
  engine='pyarrow' (multithreaded parser)      77ms     110.6MiB    1.40x  str, str
  str + city as category                       78ms      82.0MiB    1.04x  category, str
== string operations (ms)
  operation                                 object  str (arrow)  category
  name.str.contains('_a')                    260.8         54.1      53.3
  name.str.len().mean()                      292.4         25.7      24.5
  city == 'city_042'                          68.9         24.4       2.0
  groupby(city).amount.sum()                  63.3         44.4      30.0
ALL ASSERTIONS PASSED
```

* **Memory:** object strings take **3.4× the CSV size** at rest; `str` takes 1.4×, and `category` for the low-cardinality column 1.04×. The historical "5–10× RAM" rule is this at-rest overhead *plus* the transient copies of the pre-CoW era, whose share CoW removes.
* **Parsing:** ~8× faster to `str` than to object, because no Python object is created per cell. The pyarrow engine's multithreaded parser is in the same range on this file (its advantage grows with wide files and more cores).
* **Operations:** `str.contains`/`str.len` are 4–11× faster on Arrow strings (vectorized C++ kernels instead of a Python loop over objects). Equality on a `category` column is a comparison of integer codes (~2 ms against 24–69 ms).

### 2.3 Trap: the index and row-wise code

```python
"""pandas_index_pitfalls.py - the index is a join key: alignment surprises, lookup cost, and row-wise traps.

A: arithmetic and assignment align on index labels (NaN from misalignment, silent reordering).
B: lookups: unique vs non-unique index, and the return type of .loc changing with duplicates.
C: row-wise code (apply(axis=1), iterrows, itertuples) vs column vectorization; groupby apply vs transform.
"""
import time

import numpy as np
import pandas as pd

print("== A. alignment is by label, not by position")
a = pd.Series([1.0, 2.0, 3.0], index=["x", "y", "z"])
b = pd.Series([10.0, 20.0, 30.0], index=["y", "z", "w"])
print(f"  a + b -> {dict((a + b).items())}")
df = pd.DataFrame({"user": ["u1", "u2", "u3"], "score": [3.0, 1.0, 2.0]})
ranked = df["score"].sort_values()                     # index order is now 1, 2, 0
df["by_label"] = ranked                                # aligns on index: values land on their own rows
df["by_position"] = ranked.to_numpy()                  # positional: row 0 gets the smallest score
print(df.to_string(index=False).replace("\n", "\n  ").join(["  ", ""]))
assert (df["by_label"] == df["score"]).all() and not (df["by_position"] == df["score"]).all()

print("== B. index lookups: unique hash vs non-unique")
n = 1_000_000
keys = np.arange(n)
u = pd.Series(np.ones(n), index=keys)
dup = pd.Series(np.ones(n), index=np.r_[keys[:-1], 0])  # one duplicated label makes the whole index non-unique
for label, s in [("unique index", u), ("non-unique index", dup)]:
    s.loc[5]                                           # builds the hash table / engine once
    t0 = time.perf_counter()
    for k in range(1, 2001):
        s.loc[k]
    dt = (time.perf_counter() - t0) / 2000
    print(f"  {label:18} is_unique={s.index.is_unique!s:5} loc[k]: {dt * 1e6:7.1f} us  "
          f"type(loc[0]) = {type(s.loc[0]).__name__}")

print("== C. row-wise vs vectorized, 200k rows")
m = 200_000
rng = np.random.default_rng(0)
d = pd.DataFrame({"price": rng.random(m) * 100, "qty": rng.integers(1, 10, m), "g": rng.integers(0, 2_000, m)})


def timed(fn):
    t0 = time.perf_counter()
    r = fn()
    return r, time.perf_counter() - t0


r_vec, t_vec = timed(lambda: d["price"] * d["qty"])
r_apply, t_apply = timed(lambda: d.apply(lambda r: r["price"] * r["qty"], axis=1))
r_iter, t_iter = timed(lambda: [r.price * r.qty for r in d.itertuples(index=False)])
r_rows, t_rows = timed(lambda: [r["price"] * r["qty"] for _, r in d.iterrows()])
assert np.allclose(r_vec, r_apply) and np.allclose(r_vec, r_iter) and np.allclose(r_vec, r_rows)
for label, t in [("price * qty (vectorized)", t_vec), ("itertuples()", t_iter), ("apply(axis=1)", t_apply),
                 ("iterrows()", t_rows)]:
    print(f"  {label:34} {t * 1e3:9.1f} ms  ({t / t_vec:7.0f}x)")
z_apply, t_ga = timed(lambda: d.groupby("g", group_keys=False)["price"].apply(lambda s: (s - s.mean()) / s.std()))
z_tr, t_gt = timed(lambda: (d["price"] - d.groupby("g")["price"].transform("mean"))
                   / d.groupby("g")["price"].transform("std"))
assert np.allclose(z_apply.sort_index(), z_tr)
print(f"  per-group z-score, groupby.apply(lambda)   {t_ga * 1e3:9.1f} ms")
print(f"  per-group z-score, transform('mean'/'std') {t_gt * 1e3:9.1f} ms  ({t_ga / t_gt:.0f}x faster)")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. alignment is by label, not by position
  a + b -> {'w': nan, 'x': nan, 'y': 12.0, 'z': 23.0}
  user  score  by_label  by_position
    u1    3.0       3.0          1.0
    u2    1.0       1.0          2.0
    u3    2.0       2.0          3.0
== B. index lookups: unique hash vs non-unique
  unique index       is_unique=True  loc[k]:     5.7 us  type(loc[0]) = float64
  non-unique index   is_unique=False loc[k]:   327.3 us  type(loc[0]) = Series
== C. row-wise vs vectorized, 200k rows
  price * qty (vectorized)                 0.8 ms  (      1x)
  itertuples()                            94.0 ms  (    120x)
  apply(axis=1)                         1009.7 ms  (   1288x)
  iterrows()                            3026.1 ms  (   3860x)
  per-group z-score, groupby.apply(lambda)       266.1 ms
  per-group z-score, transform('mean'/'std')      11.2 ms  (24x faster)
ALL ASSERTIONS PASSED
```

* **A:** `by_label` is correct because it aligns. `by_position` shows the bug when someone "optimizes" with `.to_numpy()` after a sort: each user got another user's score, and nothing errors.
* **B:** one duplicate label made `.loc[k]` **~60× slower** (5.7 → ~330 µs) and turned its return type from a scalar into a Series. Code that does `float(s.loc[k])` breaks only when the data happens to contain a duplicate. **Pattern:** assert `index.is_unique` at load, or `verify_integrity=True` on `set_index`/`concat`.
* **C:** the row-wise ladder for 200 k rows: vectorized 0.8 ms, `itertuples` ~120×, `apply(axis=1)` ~1,300×, `iterrows` ~3,900×. Per-group z-scores with `transform('mean'/'std')` beat `groupby.apply(lambda)` by 15–24×. The rule: anything that builds a Series per row or per group is the slow path.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | After upgrading to pandas 3, some updates silently stop happening | `ChainedAssignmentError` warnings in logs; data unchanged | Chained assignment (`df[col][mask] = v`) writes to a temporary under CoW | One `.loc[mask, col] = v` call | Run tests with `-W error::pandas.errors.ChainedAssignmentError` |
| F2 🔥 | OOM reading a CSV that's 1/4 of RAM | RSS ≈ 3–5× file size during read | object-dtype strings; legacy code forcing `dtype=object` | Default `str`, `category` for low cardinality, `engine="pyarrow"`, `usecols=` | Budget memory per column type; test with production files |
| F3 | Row-wise reduction mysteriously slow; `PerformanceWarning: highly fragmented` | `df._mgr.nblocks` in the hundreds | Column-by-column inserts | Build from a dict / `pd.concat(axis=1)` once; `df = df.copy()` to consolidate | Lint against `df[...] =` inside loops |
| F4 🔥 | NaNs appear after arithmetic between two frames | Values present in both inputs become NaN | Index misalignment (different labels or dtypes of labels) | `reset_index(drop=True)` deliberately, or `align`/`join` explicitly | Assert identical indexes before arithmetic |
| F5 | Code works in tests, crashes in prod with `TypeError: cannot convert Series to float` | `.loc[k]` returned a Series | A duplicate label in production data | Enforce uniqueness; use `.at` for scalar access | `verify_integrity=True`; schema checks on keys |
| F6 ⚡ | Batch job hours long; CPU on one core | Profile dominated by `apply`, `iterrows`, `groupby.apply` | Python callback per row or group | Vectorize, `transform`, `np.where`; move to Polars/DuckDB | Code review rule: no `axis=1` apply in pipelines |
| F7 | Mixed missing-value semantics after upgrade | `None` vs `NaN` comparisons differ; `isna` counts change | `str` dtype uses NaN as its missing value | Normalize with `fillna`/`isna`; compare via `.isna()` | Golden tests on null handling |
| F8 | "Copy" of a frame still shares data with the original | Writes via NumPy (`df.to_numpy()` then mutate) affect another frame | `to_numpy()` may return a view of a block; under CoW it's marked read-only | Write through pandas APIs, or `to_numpy(copy=True)` | Treat `to_numpy()` results as read-only |

**Debugging toolkit.** `df.memory_usage(deep=True)` gives true bytes per column (shallow under-counts object columns 8×, 03.4). `df._mgr.nblocks` and `df._mgr.blocks` (internal, but invaluable) show layout. `df.index.is_unique` / `is_monotonic_increasing` show which lookup engine applies. `pd.show_versions()` reports the pyarrow version backing `str`.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "What does Copy-on-Write actually change for a production pipeline?"</b></summary>

**Initial Prompt.** A team is upgrading 200 k lines of pandas 1.x/2.x code to pandas 3. What breaks, what gets faster, and what do you audit first?

**L5 Answer.** "CoW avoids copies, so things get faster. Nothing else changes."

**Why L5 Crashes at Scale.** CoW changes *semantics*. Every chained assignment (`df["x"][mask] = v`, `df[df.a > 0]["b"] = 1`) silently stops modifying the original and only warns. In large codebases those patterns hide in feature-engineering steps, so outputs change without a crash.

**L7 Principal Defense.** Audit for semantics first, then harvest performance. Run the suite with `ChainedAssignmentError` promoted to an error, and rewrite each hit as a single `.loc` call. Also look for code that mutates `to_numpy()` results, which are read-only views under CoW. Then exploit the wins: method chains are lazy (measured 0 MiB for rename → reset_index → set_axis), and the first write copies only the written column (15.3 MiB, not 153). Remove the defensive `.copy()` calls that existed only to dodge `SettingWithCopyWarning`; they now cost a real copy for nothing.

</details>

<details><summary><b>Q2 · "Explain the '5–10× RAM rule' and whether it still holds in pandas 3."</b></summary>

**Initial Prompt.** A 20 GB CSV needs processing on a 64 GB box. Will pandas 3 fit?

**L5 Answer.** "No. pandas needs 5–10× the data size, so use Spark."

**Why L5 Crashes at Scale.** The rule mixes two causes with different fixes: (1) at-rest representation (object strings at ~3.4× the CSV here, 64-bit defaults) and (2) transient copies during operations (pre-CoW defensive copies, temporaries). Treating it as a constant leads to over-provisioning, or to unnecessary cluster migrations.

**L7 Principal Defense.** Re-measure with pandas 3 settings. Arrow-backed `str` brought at-rest size to 1.4× and `category` to ~1.0× (measured), and CoW removes most transient copies. Add `usecols`, explicit narrow dtypes (`int32`, `float32`, `category`), and chunked or streamed reading (`pd.read_csv(chunksize=)`, or better, `pyarrow.dataset` / Polars `scan_csv`, 03.2). A 20 GB CSV then needs ~20–30 GB peak in pandas 3, which fits. If the job is relational (joins, group-bys) rather than pandas-specific, run it in DuckDB or Polars streaming with bounded memory and keep pandas for the last mile.

</details>

<details><summary><b>Q3 · "Why does `df.iloc[i]` in a loop take forever?"</b></summary>

**Initial Prompt.** A scoring loop does `for i in range(len(df)): row = df.iloc[i]; score(row)` over 2 M rows.

**L5 Answer.** "Python loops are slow; use `iterrows`."

**Why L5 Crashes at Scale.** `iterrows` is the *same* mechanism, building a Series per row (measured ~3,900× slower than vectorized for a two-column product). Each row access touches every block, and finds a common dtype (often object, boxing every value) and allocates index objects.

**L7 Principal Defense.** pandas is column-major (blocks are 2-D arrays of column vectors), so row access is the worst access pattern. Rewrite the scorer to take columns (`score(df["a"].to_numpy(), df["b"].to_numpy())`), vectorize the arithmetic, and move true per-row logic into a compiled kernel (02.2) or a Polars expression (03.2). If you must iterate, `itertuples(index=False)` is ~30× faster than `iterrows` (measured 120× vs 3,900×), because it yields plain tuples.

</details>

<details><summary><b>Q4 · "Two DataFrames with the same rows produce NaNs when subtracted. Debug it."</b></summary>

**Initial Prompt.** `delta = today - yesterday` gives NaN for half the rows, though both frames have the same 1 M customers.

**L5 Answer.** "There must be missing data; use `fillna(0)`."

**Why L5 Crashes at Scale.** `fillna(0)` turns a join bug into a silent *wrong answer*: customers whose labels don't match get a delta of `today - 0`. The NaNs are alignment, not missing data.

**L7 Principal Defense.** pandas aligns on index labels before arithmetic, so this is an outer join. Labels that differ in value or type (e.g. `"00123"` vs `123`, int64 vs str after a CSV round trip, a reset vs a non-reset index) don't match. Diagnose with `today.index.symmetric_difference(yesterday.index)` and dtype checks. Fix by making the key explicit: `set_index("customer_id")` on both with a verified dtype, then `today.sub(yesterday, fill_value=...)` only where a missing side is semantically 0. Prevent it with schema checks on key columns, and prefer explicit `merge`/`join` (or SQL in DuckDB) when two datasets are combined, so the join type is in the code.

</details>

<details><summary><b>Q5 · "Should our new service use pandas, Polars or DuckDB?"</b></summary>

**Initial Prompt.** A feature-computation service processes 50 M-row daily batches and serves ad-hoc analyst queries.

**L5 Answer.** "pandas: everyone knows it."

**Why L5 Crashes at Scale.** pandas is eager (every step materializes) and mostly single-threaded, with no query optimizer, so it reads all columns and rows and can't push filters into Parquet. The measured gaps on this laptop: a group-by 3.7× slower than Polars on 12 threads, rolling windows 13× slower, Parquet filter queries 30× slower than DuckDB (03.3), and more memory throughout.

**L7 Principal Defense.** Choose per layer. Use DuckDB for SQL-shaped work over Parquet (joins, aggregations, window functions, out-of-core spilling) and analyst access. Use Polars for expression-heavy transformation pipelines and streaming. Use pandas at the edges, where libraries require it (scikit-learn, statsmodels, plotting), converting via Arrow with zero copy (`to_pandas(types_mapper=pd.ArrowDtype)`, 02.3). Standardize the interchange on Arrow so engines can be swapped per step without serialization, and keep business logic in SQL or expressions rather than in row-wise Python.

</details>

<details><summary><b>Q6 · "What is the BlockManager and why should a backend engineer care?"</b></summary>

**Initial Prompt.** Explain pandas' internal layout and one production consequence.

**L5 Answer.** "It stores columns in NumPy arrays."

**Why L5 Crashes at Scale.** The details have operational consequences. Same-dtype columns live together in 2-D blocks, so inserts fragment the frame, consolidation triggers copies, row access gathers across blocks, and extension types bypass consolidation entirely. Teams that add columns in loops see ~4× slower row reductions (measured) and memory spikes when pandas consolidates.

**L7 Principal Defense.** A DataFrame is axes plus a `BlockManager` holding blocks per dtype. NumPy blocks are 2-D (columns × rows); Arrow and other extension arrays are 1-D blocks. Columns are cheap views; rows are expensive gathers; inserting a column adds a block (300 inserts → 300 blocks). Consolidation, which merges blocks, happens on certain operations and costs a full copy of the merged data. Production rules follow: construct frames in one shot, avoid row-wise access, and expect extension-typed columns to behave as independent arrays, which they are, and which is good for Arrow interop.

</details>

<details><summary><b>Q7 · "A pipeline's `.loc` lookups got 60× slower overnight with no code change. Why?"</b></summary>

**Initial Prompt.** A per-request feature lookup does `series.loc[customer_id]` and its p99 jumped.

**L5 Answer.** "The data got bigger."

**Why L5 Crashes at Scale.** Size alone wouldn't do it; hash lookups are O(1). Something changed the *index engine*: a duplicate label, or a lost monotonicity, switches pandas to slower paths. A duplicate also changes the return type to a Series, which may later crash or silently produce lists.

**L7 Principal Defense.** Check `index.is_unique` and `is_monotonic_increasing`. One duplicate turned 5.7 µs into ~330 µs per lookup (measured), and `type(loc[k])` from scalar to Series. Fix the upstream dedup, and enforce `verify_integrity=True` or an explicit `assert s.index.is_unique` at load. For a serving path, don't use pandas at all: build a `dict` or a NumPy-backed sorted array with `searchsorted` once, or use a real key-value store, to get predictable latency.

</details>

<details><summary><b>Q8 · "How do you make pandas and Arrow engines coexist without copies?"</b></summary>

**Initial Prompt.** The pipeline uses DuckDB for joins, Polars for transforms and pandas for a scikit-learn step.

**L5 Answer.** "Convert to pandas once and keep everything in pandas."

**Why L5 Crashes at Scale.** Converting everything to pandas forfeits the engines' parallelism and pushdown, and pays the NumPy conversion for numerics (~100–130 ms per 20 M rows, 02.3) and object-ification if legacy dtypes sneak in.

**L7 Principal Defense.** Keep Arrow as the backbone. DuckDB → Arrow (`to_arrow_table()`, ~26 ms for 5 M rows here) → Polars zero-copy for numerics. Hand pandas only the columns the scikit-learn step needs, via `to_pandas(types_mapper=pd.ArrowDtype)` (zero copy) or NumPy-backed if the estimator needs float64 arrays (one deliberate copy). pandas 3's `str` columns already share Arrow buffers. Verify zero copy with buffer-address checks in integration tests (02.3), and document each conversion point in the pipeline graph.

</details>

---

## 5. Invariants Checklist

- [ ] pandas 3: Copy-on-Write is always on. Chained assignment never writes through; use one `.loc`/`.iloc` call.
- [ ] Derived objects are lazy copies. The first write copies only what's written, so drop defensive `.copy()`.
- [ ] Strings default to Arrow-backed `str` (1.4× CSV size here vs 3.4× for object). Use `category` for low cardinality.
- [ ] DataFrames are column-major blocks: columns are cheap, rows expensive. Never iterate rows in production code.
- [ ] Build frames once from a dict of columns. Column-by-column inserts fragment the BlockManager.
- [ ] Arithmetic and assignment align on index labels. Make join keys explicit and verified.
- [ ] One duplicate label switches the index to slow lookups and changes `.loc` return types. Enforce uniqueness.
- [ ] pandas is eager and largely single-threaded. Use DuckDB/Polars for heavy relational work and pandas at the edges via Arrow.

---

## 6. References

- pandas 3.0 release notes (what's new) — https://pandas.pydata.org/docs/whatsnew/v3.0.0.html
- PDEP-7, Consistent copy/view semantics with Copy-on-Write — https://pandas.pydata.org/pdeps/0007-copy-on-write.html
- PDEP-14, Dedicated string data type for pandas 3.0 — https://pandas.pydata.org/pdeps/0014-string-dtype.html
- pandas user guide, Copy-on-Write — https://pandas.pydata.org/docs/user_guide/copy_on_write.html
- pandas user guide, Scaling to large datasets — https://pandas.pydata.org/docs/user_guide/scale.html
- pandas user guide, Enhancing performance — https://pandas.pydata.org/docs/user_guide/enhancingperf.html
- pandas PyArrow functionality (`ArrowDtype`, `str`) — https://pandas.pydata.org/docs/user_guide/pyarrow.html
- W. McKinney, "Apache Arrow and the '10 Things I Hate About pandas'" (2017), the origin of the 5–10× rule — https://wesmckinney.com/blog/apache-arrow-pandas-internals/
