# 04.4 · The Modern Python Data Stack: Parquet Internals, PyIceberg, delta-rs, and dbt/Airflow

> **Folder 04 · Distributed Data Engineering: PySpark, Beam, Ray & Lakehouse**
> **Measured on:** pyarrow 26.0.0 (Parquet writer "parquet-cpp-arrow"), PyIceberg 0.12.0 (SQLite catalog, local warehouse), deltalake (delta-rs) 1.6.6, CPython 3.14.5, i5-11260H, Windows 11.
> **Spec sources:** the Apache Parquet format (row groups, pages, encodings, statistics), the Iceberg table spec (metadata, manifests, snapshots), and the Delta transaction-log protocol.
> ⚠ **Not executed here:** dbt and Airflow. §1.5 and Q8 cover their role from first principles; no listing.

---

## 0. Orientation & the JVM/C++ Bridge

The lakehouse is three layers. **Parquet** files (immutable, columnar, self-describing) hold data. A **table format** (Iceberg or Delta) adds a transaction log of which files make up each version of the table: snapshots, schema evolution, partition evolution, deletes and time travel. **Engines** (Spark, Trino, DuckDB, Polars, PyIceberg, delta-rs, Snowflake, BigQuery) read and write through it. **Orchestration and modeling** (Airflow, dbt) schedule and version the transformations. Everything in Folders 02–03 about pushdown and zero copy pays off only if the files and metadata are laid out for it.

| Concept | Python stack | JVM analogue | Notes |
|---|---|---|---|
| Columnar file | Parquet via pyarrow / Polars / DuckDB writers | parquet-mr | same format |
| Table format | PyIceberg, delta-rs (`deltalake`) | Iceberg Java, Delta Spark | no JVM needed in Python |
| Catalog | SQL (SQLite/Postgres), REST, Glue, Hive | same | atomic pointer swap = commit |
| Transformations | dbt (SQL models), Polars/DuckDB jobs | Spark jobs | — |
| Orchestration | Airflow, Dagster, Prefect | Oozie, Airflow | idempotent, partition-addressed tasks |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 Inside a Parquet file

```text
 "PAR1"
 Row group 0 (e.g. 250k rows)
   Column chunk ts        [dictionary page?] [data page][data page]...   codec per chunk (ZSTD, SNAPPY, ...)
   Column chunk category  [dictionary page]  [data pages: RLE/bit-packed dictionary indices]
   Column chunk user_id   ...
 Row group 1 ...
 [Column index + Offset index per page (optional "page index")]   [Bloom filters (optional)]
 Footer: FileMetaData (Thrift): schema, row groups -> column chunk metadata:
         encodings, codec, offsets, uncompressed/compressed sizes, statistics (min, max, null_count)
 footer length (4 B) + "PAR1"
```

* **Encodings.** Dictionary encoding (RLE_DICTIONARY, with indices RLE/bit-packed) is the writer's default. It falls back to PLAIN once a chunk's dictionary grows too large (here every column reports `PLAIN/RLE/RLE_DICTIONARY`). DELTA_BINARY_PACKED, DELTA_BYTE_ARRAY and BYTE_STREAM_SPLIT can be requested per column.
* **Statistics** per column chunk drive row-group skipping (03.2, 03.3). For floats the spec writes `-0.0` as the min when zero is present; the listing's `amount` column shows `min=-0.0`.
* **Compression** is per column chunk, after encoding. Reads decompress only the projected chunks of the row groups that survive pruning.

### 1.2 Writer choices that matter

| Choice | Effect (measured, 2 M rows) |
|---|---|
| Codec | zstd 18.6 MiB (3.6× vs Arrow memory), snappy 27.6, lz4 27.0, gzip 19.3. **gzip writes ~40× slower** (~19.5 s vs ~0.5 s) for no size gain over zstd |
| Sort order | sorted by (category, user_id): 21.7 MiB, 15 of 20 row groups single-valued in `category`; shuffled: 27.1 MiB, 0 of 20 |
| Row-group size | 1 M rows: smallest file (14.5 MiB) but a filtered read took ~25 ms; 100 k rows: 5.2 ms; 10 k rows: 7.3 ms (more footer and page overhead) |

### 1.3 Iceberg: metadata tree and snapshots

```text
 catalog (SQLite here)  ->  current metadata pointer: .../metadata/00003-....metadata.json
 metadata.json: schemas (with field ids), partition specs, snapshots[], current-snapshot-id, properties
   snapshot -> manifest list (snap-*.avro): one entry per manifest + partition summaries
       manifest (*-m*.avro): one entry per data file: path, partition values, row count,
                             column lower/upper bounds, null counts   <- file-level pruning lives here
           data files (Parquet)
 commit = write new metadata.json + atomically swap the catalog pointer (optimistic concurrency)
```

Planning prunes at two levels before opening any Parquet file. Partition summaries and values skip files outside `day == 3` (3 of 30 planned, measured). Column bounds skip files whose `id` range can't match (10 of 30). Deletes in PyIceberg 0.12 rewrite affected files (copy-on-write). Iceberg v2 also defines merge-on-read position and equality delete files, and v3 adds deletion vectors. Schema evolution is metadata-only: the added `discount` column reads as null for 1,800 old rows without rewriting them.

### 1.4 Delta Lake: the transaction log

```text
 table/
   _delta_log/00000000000000000000.json  {"protocol":...}{"metaData":...}{"add":{"path":...,"stats":...}}...
              00000000000000000001.json  {"add":...}               (one JSON commit per write)
              ...  00000000000000000010.checkpoint.parquet  (periodic snapshot of all live actions)
   day=3/part-....parquet ...
 version N = replay(checkpoint <= N) + JSON commits up to N: live files = adds - removes
 commit = put-if-absent of the next JSON file (optimistic concurrency; object stores need a coordinator or conditional PUT)
```

Measured: 3 appends = 3 JSON commits and 30 files. `delete` added a version (copy-on-write rewrite of affected files). `optimize.compact()` bin-packed 18 live files into 6. `vacuum(dry_run)` listed 30 unreferenced files, which are deletable only once you give up time travel to the versions that used them.

### 1.5 dbt and Airflow (⚠ not executed here)

* **dbt** compiles Jinja-templated SQL models into DAG-ordered `CREATE TABLE/VIEW AS` or `MERGE` statements against an engine (DuckDB, Spark, Snowflake, BigQuery), with tests (unique, not-null, relationships), documentation and lineage. Incremental models use `is_incremental()` with a high-water mark or a partition filter. The engine does the work, so all of Folder 03's pushdown rules apply.
* **Airflow** schedules tasks, not data. Production rules follow from that: tasks must be **idempotent and partition-addressed** (a run for `ds=2026-10-28` overwrites exactly that partition, via Iceberg/Delta overwrite or MERGE), heavy compute runs in the engine rather than the Airflow worker, and backfills are just runs over past partitions.

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Parquet: codecs, encodings, sort order, row groups

```python
"""parquet_internals.py - what's inside a Parquet file and which writer choices change size and read cost.

A: compression codecs: file size, write and read time.  B: encodings and statistics per column chunk.
C: sort order: the same rows sorted vs shuffled (compression + min/max selectivity).
D: row-group size vs filtered-read cost (pyarrow reads only row groups whose statistics can match).
"""
import os
import shutil
import tempfile
import time

import numpy as np
import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.parquet as pq

N = 2_000_000
rng = np.random.default_rng(0)
cats = np.array(["electronics", "grocery", "toys", "garden", "books", "apparel"])
table = pa.table({"ts": np.arange(N, dtype=np.int64) * 1000,
                  "category": pa.array(cats[rng.integers(0, len(cats), N)]),
                  "user_id": rng.integers(0, 500_000, N),
                  "amount": np.round(rng.random(N) * 200, 2)})
tmp = tempfile.mkdtemp()
raw_mb = table.nbytes / 2**20


def timed(fn):
    t0 = time.perf_counter()
    r = fn()
    return r, time.perf_counter() - t0


print(f"pyarrow {pa.__version__}; {N:,} rows, {raw_mb:.1f} MiB in Arrow memory")
warm = os.path.join(tmp, "warm.parquet")
pq.write_table(table.slice(0, 1000), warm)
pq.read_table(warm)                                       # first-call initialization outside the timings
print("== A. compression codecs")
print(f"  {'codec':10} {'file MiB':>9} {'ratio':>6} {'write':>8} {'read':>8}")
for codec in ("none", "snappy", "lz4", "zstd", "gzip"):
    path = os.path.join(tmp, f"t_{codec}.parquet")
    _, tw = timed(lambda: pq.write_table(table, path, compression=codec, row_group_size=250_000))
    _, tr = timed(lambda: pq.read_table(path))
    mb = os.path.getsize(path) / 2**20
    print(f"  {codec:10} {mb:9.1f} {raw_mb / mb:6.2f} {tw * 1e3:6.0f}ms {tr * 1e3:6.0f}ms")

print("== B. column chunks of row group 0 (zstd file)")
md = pq.ParquetFile(os.path.join(tmp, "t_zstd.parquet")).metadata
print(f"  {md.num_row_groups} row groups, {md.num_columns} columns, created by {md.created_by.split(' ')[0]}")
for i in range(md.num_columns):
    c = md.row_group(0).column(i)
    st = c.statistics
    print(f"  {c.path_in_schema:9} encodings={'/'.join(c.encodings):34} "
          f"{c.total_uncompressed_size / 2**10:7.0f} KiB -> {c.total_compressed_size / 2**10:6.0f} KiB  "
          f"min={st.min!r:>14} max={st.max!r:>14}")

print("== C. sort order: same rows, sorted by (category, user_id) vs shuffled")
shuffled = table.take(pa.array(rng.permutation(N)))
by_cat = table.sort_by([("category", "ascending"), ("user_id", "ascending")])
for label, t in (("shuffled", shuffled), ("sorted", by_cat)):
    path = os.path.join(tmp, f"order_{label}.parquet")
    pq.write_table(t, path, compression="zstd", row_group_size=100_000)
    m = pq.ParquetFile(path).metadata
    ci = m.schema.names.index("category")
    single = sum(1 for g in range(m.num_row_groups)
                 if m.row_group(g).column(ci).statistics.min == m.row_group(g).column(ci).statistics.max)
    print(f"  {label:9} {os.path.getsize(path) / 2**20:6.1f} MiB; row groups with a single category value: "
          f"{single}/{m.num_row_groups}")

print("== D. filtered read: category == 'toys' AND user_id < 5000, by row-group size (sorted data)")
for rg in (1_000_000, 100_000, 10_000):
    path = os.path.join(tmp, f"rg_{rg}.parquet")
    pq.write_table(by_cat, path, compression="zstd", row_group_size=rg)
    flt = (pc.field("category") == "toys") & (pc.field("user_id") < 5000)
    pq.read_table(path, filters=flt)
    got, dt = timed(lambda: pq.read_table(path, filters=flt))
    print(f"  row_group_size={rg:>9,}: {pq.ParquetFile(path).metadata.num_row_groups:4} groups, "
          f"{os.path.getsize(path) / 2**20:5.1f} MiB, read {dt * 1e3:6.1f} ms -> {got.num_rows:,} rows")
expect = by_cat.filter((pc.field("category") == "toys") & (pc.field("user_id") < 5000)).num_rows
assert got.num_rows == expect
shutil.rmtree(tmp)
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
pyarrow 26.0.0; 2,000,000 rows, 66.1 MiB in Arrow memory
== A. compression codecs
  codec       file MiB  ratio    write     read
  none            39.2   1.68    446ms     41ms
  snappy          27.6   2.40    495ms     37ms
  lz4             27.0   2.45    490ms     38ms
  zstd            18.6   3.56    552ms     39ms
  gzip            19.3   3.43  19668ms     46ms
== B. column chunks of row group 0 (zstd file)
  8 row groups, 4 columns, created by parquet-cpp-arrow
  ts        encodings=PLAIN/RLE/RLE_DICTIONARY              2218 KiB ->    693 KiB  min=             0 max=     249999000
  category  encodings=PLAIN/RLE/RLE_DICTIONARY                93 KiB ->     88 KiB  min=     'apparel' max=        'toys'
  user_id   encodings=PLAIN/RLE/RLE_DICTIONARY              2099 KiB ->   1075 KiB  min=             6 max=        499989
  amount    encodings=PLAIN/RLE/RLE_DICTIONARY               613 KiB ->    520 KiB  min=          -0.0 max=         200.0
== C. sort order: same rows, sorted by (category, user_id) vs shuffled
  shuffled    27.1 MiB; row groups with a single category value: 0/20
  sorted      21.7 MiB; row groups with a single category value: 15/20
== D. filtered read: category == 'toys' AND user_id < 5000, by row-group size (sorted data)
  row_group_size=1,000,000:    2 groups,  14.5 MiB, read   25.9 ms -> 3,263 rows
  row_group_size=  100,000:   20 groups,  21.7 MiB, read    5.2 ms -> 3,263 rows
  row_group_size=   10,000:  200 groups,  24.1 MiB, read    7.3 ms -> 3,263 rows
ALL ASSERTIONS PASSED
```

* zstd is the default choice: the best ratio here at the same speed as snappy and lz4. gzip's ~19.5 s write makes it the wrong choice for anything hot.
* Sorting by the common filter keys shrank the file by 20 % *and* made 15 of 20 row groups single-valued for `category`, so a `category = ...` predicate prunes them from statistics alone.
* Row-group size is a trade-off between compression and footer overhead on one side and pruning granularity on the other. ~100 k–1 M rows (tens to a few hundred MB uncompressed) is the usual target; here the 100 k layout read the selective filter ~5× faster than 1 M.

### 2.2 Table formats: snapshots, pruning, deletes, evolution, compaction

```python
"""iceberg_delta_tables.py - table formats over Parquet: snapshots, pruning, deletes, schema evolution, compaction.

Apache Iceberg via PyIceberg (SQLite catalog, local warehouse) and Delta Lake via delta-rs (`deltalake`), both on
the local filesystem. Every write is an atomic commit of metadata that points at immutable Parquet files.
"""
import glob
import os
import shutil
import tempfile

import numpy as np
import pyarrow as pa
from deltalake import DeltaTable, write_deltalake
from pyiceberg.catalog.sql import SqlCatalog
from pyiceberg.partitioning import PartitionField, PartitionSpec
from pyiceberg.schema import Schema
from pyiceberg.transforms import IdentityTransform
from pyiceberg.types import DoubleType, IntegerType, LongType, NestedField

root = tempfile.mkdtemp()


def batch(start, n=1_000):
    ids = np.arange(start, start + n)
    return pa.table({"id": pa.array(ids, pa.int64()), "day": pa.array(ids % 10, pa.int32()),
                     "qty": pa.array(ids % 5, pa.int64())})


def count(pattern):
    return len(glob.glob(pattern, recursive=True))


print("== Apache Iceberg (PyIceberg, SQLite catalog)")
wh = os.path.join(root, "iceberg").replace("\\", "/")
os.makedirs(wh)
cat = SqlCatalog("local", uri=f"sqlite:///{wh}/catalog.db", warehouse=wh)   # plain path: file:/// breaks on Windows
cat.create_namespace("shop")
schema = Schema(NestedField(1, "id", LongType(), required=False), NestedField(2, "day", IntegerType(), required=False),
                NestedField(3, "qty", LongType(), required=False))
spec = PartitionSpec(PartitionField(source_id=2, field_id=1000, transform=IdentityTransform(), name="day"))
t = cat.create_table("shop.orders", schema=schema, partition_spec=spec)
for i in range(3):
    t.append(batch(i * 1_000))                            # each append = one snapshot, one file per partition
tdir = f"{wh}/shop/orders"
print(f"  after 3 appends: {len(t.snapshots())} snapshots, {count(tdir + '/data/**/*.parquet')} data files, "
      f"{count(tdir + '/metadata/*.metadata.json')} metadata.json, {count(tdir + '/metadata/snap-*.avro')} manifest lists, "
      f"{count(tdir + '/metadata/*-m*.avro')} manifests")
all_files = len(list(t.scan().plan_files()))
part = len(list(t.scan(row_filter="day == 3").plan_files()))
rng_ = len(list(t.scan(row_filter="id < 1000").plan_files()))
print(f"  planning: full scan {all_files} files; day == 3 -> {part} files (partition pruning); "
      f"id < 1000 -> {rng_} files (column min/max in manifests)")
assert part == 3 and rng_ == 10
t.delete(delete_filter="qty < 2")
rows = t.scan().to_arrow().num_rows
print(f"  delete qty < 2: {rows:,} rows remain, snapshots {[s.summary.operation.value for s in t.snapshots()]}")
with t.update_schema() as u:
    u.add_column("discount", DoubleType())                # metadata-only: old files are not rewritten
t = cat.load_table("shop.orders")
t.append(batch(3_000).append_column("discount", pa.array(np.full(1_000, 0.1))))
cur = t.scan().to_arrow()
print(f"  added column 'discount': {cur.num_rows:,} rows, nulls in old rows = {cur['discount'].null_count:,}")
first = t.snapshots()[0].snapshot_id
print(f"  time travel to the first snapshot: {t.scan(snapshot_id=first).to_arrow().num_rows:,} rows")
assert rows == 1_800 and cur["discount"].null_count == 1_800

print("== Delta Lake (delta-rs)")
dl = os.path.join(root, "delta")
for i in range(3):
    write_deltalake(dl, batch(i * 1_000), partition_by=["day"], mode="append")
d = DeltaTable(dl)
print(f"  after 3 appends: version {d.version()}, {len(d.file_uris())} data files, "
      f"{count(os.path.join(dl, '_delta_log', '*.json'))} JSON commits in _delta_log")
d.delete("qty < 2")
d = DeltaTable(dl)
print(f"  delete qty < 2: version {d.version()}, history {[h['operation'] for h in d.history()]}, "
      f"rows {d.to_pyarrow_dataset().count_rows():,}")
print(f"  time travel to version 0: {DeltaTable(dl, version=0).to_pyarrow_dataset().count_rows():,} rows")
before = len(d.file_uris())
metrics = d.optimize.compact()                            # bin-pack small files per partition
d = DeltaTable(dl)
print(f"  optimize.compact(): live files {before} -> {len(d.file_uris())} "
      f"(added {metrics['numFilesAdded']}, removed {metrics['numFilesRemoved']}), version {d.version()}")
stale = d.vacuum(retention_hours=0, enforce_retention_duration=False, dry_run=True)
print(f"  vacuum(dry_run): {len(stale)} unreferenced files could be deleted (time travel to older versions ends then)")
assert d.to_pyarrow_dataset().count_rows() == 1_800
shutil.rmtree(root, ignore_errors=True)
print("ALL ASSERTIONS PASSED")
```

Output (deterministic counts; one measured run):

```text
== Apache Iceberg (PyIceberg, SQLite catalog)
  after 3 appends: 3 snapshots, 30 data files, 4 metadata.json, 3 manifest lists, 3 manifests
  planning: full scan 30 files; day == 3 -> 3 files (partition pruning); id < 1000 -> 10 files (column min/max in manifests)
  delete qty < 2: 1,800 rows remain, snapshots ['append', 'append', 'append', 'delete']
  added column 'discount': 2,800 rows, nulls in old rows = 1,800
  time travel to the first snapshot: 1,000 rows
== Delta Lake (delta-rs)
  after 3 appends: version 2, 30 data files, 3 JSON commits in _delta_log
  delete qty < 2: version 3, history ['DELETE', 'WRITE', 'WRITE', 'WRITE'], rows 1,800
  time travel to version 0: 1,000 rows
  optimize.compact(): live files 18 -> 6 (added 6, removed 18), version 4
  vacuum(dry_run): 30 unreferenced files could be deleted (time travel to older versions ends then)
ALL ASSERTIONS PASSED
```

* Each Iceberg append wrote one file per partition (10) and one snapshot, so 3 appends gave 30 small files. That's the small-files problem streaming writers create. Compaction (Delta's `optimize.compact()` here: 18 → 6 files; Iceberg's `rewrite_data_files` in Spark) is a routine maintenance job, not an emergency fix.
* Pruning happens in metadata: 3 of 30 files for the partition predicate and 10 of 30 from column bounds, before any Parquet footer is read.
* Time travel is "read an older metadata version". It ends when vacuum or snapshot expiry deletes the files that version references.
* PyIceberg on Windows needs a plain path for a local warehouse: `file:///C:/...` produced an invalid `/C:/...` path (observed).

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | Queries slow down month by month | Planning time ↑; thousands of tiny files per partition | Streaming or micro-batch appends; no compaction | Scheduled compaction (`optimize.compact`, Iceberg `rewrite_data_files`); larger commit intervals | Alert on files per partition and average file size |
| F2 | Filters don't prune | Row groups or files scanned ≈ total | Unsorted data; statistics overlap | Sort or Z-order within partitions at write and compaction time | Layout tests on statistics (03.3) |
| F3 🔥 | Time travel or rollback fails with missing files | `FileNotFoundError` on old versions | Vacuum or snapshot expiry removed the files | Align retention with recovery needs (e.g. 7 days) | Document retention as an SLO |
| F4 🔥 | Concurrent writers clobber each other | Lost appends; conflicting commits | No atomic commit primitive (Delta on object storage without conditional PUT or a log store) | Catalog-backed Iceberg; Delta with a DynamoDB log store / conditional writes | Never let two engines commit without a shared protocol |
| F5 | Storage bill grows despite deletes | Old files retained | Copy-on-write deletes rewrite files; old versions keep the originals | Expire snapshots / vacuum; merge-on-read deletes for frequent small deletes | Track live vs total bytes |
| F6 ⚡ | Writes take forever | gzip codec; one huge row group; Python row-wise writes | Writer misconfiguration | zstd, sensible row groups, Arrow batch writes | Writer config in a shared library |
| F7 | Readers see a mix of old and new schema or break on renames | Schema mismatch errors | Column matching by name in plain Parquet | Iceberg field-id-based schema evolution; Delta column mapping | Evolve schemas only through the table format |
| F8 | Airflow backfill double-counts data | Duplicate rows after reruns | Non-idempotent `append` tasks | Partition overwrite or MERGE keyed by natural keys | Idempotency tests: run twice, assert equal |

**Debugging toolkit.** `pq.ParquetFile(f).metadata` (row groups, encodings, statistics), DuckDB `parquet_metadata()` (03.3), Iceberg `table.inspect.files()` / `snapshots()` / `scan().plan_files()`, Delta `DeltaTable.history()` / `file_uris()` / `get_add_actions()`, and the raw `_delta_log/*.json` files. They're human-readable.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why does a query that touches 1 % of a 50 TB table read 40 TB?"</b></summary>

**Initial Prompt.** An Iceberg table partitioned by day is queried by `customer_id` and a date range.

**L5 Answer.** "The engine doesn't support pushdown; switch engines."

**Why L5 Crashes at Scale.** Every modern engine pushes down. The failure is layout: within each day partition, `customer_id` is randomly distributed, so every file's min/max spans nearly all customers and nothing can be skipped (measured: 0 of 20 row groups single-valued when shuffled, 15 of 20 when sorted).

**L7 Principal Defense.** Iceberg prunes in metadata (partition values and column bounds in manifests; measured 3 of 30 and 10 of 30 files planned) and Parquet prunes row groups by statistics, but only if values are clustered. Sort or Z-order data within partitions by the secondary filter keys during compaction (Iceberg sort orders, Delta `optimize.z_order`). Keep row groups around 100 k–1 M rows (~5× faster selective reads than 1 M here). Consider bucketing (Iceberg `bucket(N, customer_id)`) for point lookups. Then verify with planned-files counts and `EXPLAIN ANALYZE` row-group counters.

</details>

<details><summary><b>Q2 · "Iceberg or Delta?"</b></summary>

**Initial Prompt.** A new lakehouse for Spark, DuckDB, Trino and Python services.

**L5 Answer.** "Delta, because we use Spark."

**Why L5 Crashes at Scale.** Engine-of-the-day choices create lock-in at the most permanent layer of the platform. The decisive factors are multi-engine support, catalog semantics, concurrency guarantees on your object store, and operational tooling.

**L7 Principal Defense.** Both store data as Parquet plus a log of file sets. Iceberg uses a catalog-mediated atomic metadata swap (REST/Glue/SQL catalogs), hidden partitioning with transforms (partition evolution without rewrites), field-id schema evolution, and broad engine support. Delta uses an ordered JSON log with checkpoints and put-if-absent commits (needs conditional writes or a log store on S3), with deep Spark/Databricks integration, and delta-rs for Python and Rust. Both have native Python clients (PyIceberg, delta-rs) that worked here without a JVM. Choose by catalog strategy and engine mix. For heterogeneous engines with a REST catalog, Iceberg is the common default in 2026. Standardize maintenance (compaction, expiry, vacuum) either way.

</details>

<details><summary><b>Q3 · "What exactly is a commit in a table format, and how do concurrent writers interact?"</b></summary>

**Initial Prompt.** Two jobs append to the same table at the same time.

**L5 Answer.** "The table format locks the table."

**Why L5 Crashes at Scale.** There's no lock. Commits are optimistic. Assuming locks leads to designs where one job blindly retries or overwrites, losing data or corrupting partitions.

**L7 Principal Defense.** A writer stages new data files, then tries to install new metadata atomically: Iceberg swaps the catalog's metadata pointer with compare-and-swap semantics, Delta writes the next numbered JSON commit with put-if-absent. If another commit won, the loser re-reads the latest state, checks for conflicts (appends usually don't conflict; overlapping deletes or overwrites do) and retries. So two appends both succeed, while two overwrites of the same partition conflict and one retries or fails. On object stores without atomic put-if-absent, Delta needs a coordination service. Design jobs so retries are idempotent.

</details>

<details><summary><b>Q4 · "Which Parquet codec and row-group size do you standardize on, and why?"</b></summary>

**Initial Prompt.** Teams use a mix of gzip, snappy and default settings.

**L5 Answer.** "gzip compresses best; use it to save storage."

**Why L5 Crashes at Scale.** Measured: gzip produced a slightly *larger* file than zstd (19.3 vs 18.6 MiB) and wrote **~40× slower** (~19.5 s vs ~0.5 s). At petabyte scale that's a fleet of writer CPU for nothing.

**L7 Principal Defense.** Standardize zstd at a moderate level (3.6× vs Arrow memory here, snappy-class read speed), with dictionary encoding left on (automatic fallback for high-cardinality columns). Target row groups of ~100 k–1 M rows (128–512 MB uncompressed for wide tables) and sort by common filter columns. Enable page indexes and bloom filters for point-lookup columns where engines use them. Encode these in a shared writer configuration and enforce them in compaction jobs.

</details>

<details><summary><b>Q5 · "Explain time travel and why it sometimes stops working."</b></summary>

**Initial Prompt.** An analyst's `VERSION AS OF 120` query worked last week and fails today.

**L5 Answer.** "The table got corrupted."

**Why L5 Crashes at Scale.** Nothing is corrupted. Time travel reads an older snapshot whose files must still exist, and maintenance (vacuum, snapshot expiry) deliberately deletes unreferenced files after a retention window.

**L7 Principal Defense.** A version is a set of file references reconstructed from the log (Delta) or metadata.json snapshots (Iceberg); measured, version 0 still showed 1,000 rows after later deletes. `vacuum`/`expire_snapshots` remove files not referenced by retained versions (30 such files in the dry run). Set retention by recovery and audit needs, and expose it as a documented SLO. For long-term reproducibility, *tag* snapshots (Iceberg tags and branches) or copy critical snapshots, rather than relying on the default retention.

</details>

<details><summary><b>Q6 · "Your streaming job writes to Delta every 10 seconds. What breaks after a month?"</b></summary>

**Initial Prompt.** A micro-batch writer appends ~1 MB per commit.

**L5 Answer.** "Nothing. Delta handles streaming."

**Why L5 Crashes at Scale.** 8,640 commits a day, each adding small files per partition, means hundreds of thousands of tiny files, a growing log, planning and listing overhead, and poor compression. Readers slow down steadily (measured shape: 3 appends produced 30 files across 10 partitions).

**L7 Principal Defense.** Batch commits (a 1–5 minute trigger, or larger in-memory buffers), partition coarsely, run scheduled compaction (`optimize.compact`, measured 18 → 6 files), and checkpoint the log (Delta writes Parquet checkpoints every N commits). Consider Iceberg with merge-on-read for high-frequency upserts. Monitor files per partition, average file size and planning time as SLIs.

</details>

<details><summary><b>Q7 · "How do schema changes work without rewriting data?"</b></summary>

**Initial Prompt.** Add a `discount` column to a 200 TB table without downtime.

**L5 Answer.** "Rewrite the table with the new column."

**Why L5 Crashes at Scale.** A 200 TB rewrite costs days of compute and blocks writers. Plain Parquet directories also match columns *by name*, so renames break readers.

**L7 Principal Defense.** Table formats version the schema in metadata. Iceberg assigns stable field IDs, so add, rename and drop are metadata-only and old files read new columns as null. Measured: `discount` was added and 1,800 old rows read null with no rewrite. Delta does the same with column mapping. Evolve schemas through the format's API only, keep consumers tolerant of nullable new columns, and backfill values with a partition-scoped MERGE if needed.

</details>

<details><summary><b>Q8 · "What do dbt and Airflow each own in a well-designed platform?"</b></summary>

**Initial Prompt.** A team runs Pandas transformations inside Airflow PythonOperators.

**L5 Answer.** "Airflow can run anything; keep the Python there."

**Why L5 Crashes at Scale.** Airflow workers become compute nodes without the memory, parallelism or retries the work needs. Transformations aren't tested or versioned as models, and non-idempotent appends double-count on retries.

**L7 Principal Defense.** dbt owns *what* the data is: SQL models compiled against an engine (DuckDB, Spark, a warehouse), with tests, documentation, lineage and incremental logic. Airflow (or Dagster) owns *when*: scheduling, dependencies, retries, SLAs and backfills by partition. The heavy compute runs in the engine, or in Ray/Spark for Python-heavy steps. Every task is idempotent and partition-addressed: overwrite or MERGE `ds=…` into Iceberg/Delta. Validate the contract by running each task twice in CI and asserting identical outputs.

</details>

---

## 5. Invariants Checklist

- [ ] Parquet = row groups → column chunks → pages, with a footer of schema and statistics. Readers prune row groups by min/max.
- [ ] Use zstd by default. gzip was ~40× slower to write for a larger file here.
- [ ] Sort within partitions by filter keys; it shrinks files and makes statistics selective.
- [ ] Row groups of ~100 k–1 M rows balance compression against pruning granularity.
- [ ] A table version is a set of immutable files plus metadata. Commits are optimistic atomic metadata swaps.
- [ ] Iceberg prunes in manifests (partition values and column bounds) before touching Parquet.
- [ ] Schema evolution is metadata-only through the format (field IDs / column mapping).
- [ ] Compaction and retention (vacuum/expiry) are scheduled maintenance. Retention bounds time travel.
- [ ] Orchestrated tasks must be idempotent and partition-addressed.

---

## 6. References

- Apache Parquet file format — https://parquet.apache.org/docs/file-format/
- Parquet encodings — https://parquet.apache.org/docs/file-format/data-pages/encodings/
- Parquet page index — https://parquet.apache.org/docs/file-format/pageindex/
- pyarrow `parquet.write_table` (codecs, row groups, statistics, page index) — https://arrow.apache.org/docs/python/generated/pyarrow.parquet.write_table.html
- Apache Iceberg table spec — https://iceberg.apache.org/spec/
- PyIceberg documentation — https://py.iceberg.apache.org/
- Delta Lake transaction protocol — https://github.com/delta-io/delta/blob/master/PROTOCOL.md
- delta-rs Python documentation — https://delta-io.github.io/delta-rs/
- dbt documentation, incremental models — https://docs.getdbt.com/docs/build/incremental-models
- Apache Airflow best practices (idempotency) — https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html
- M. Armbrust et al., "Delta Lake: High-Performance ACID Table Storage over Cloud Object Stores", PVLDB 13(12), 2020 — https://www.vldb.org/pvldb/vol13/p3411-armbrust.pdf
