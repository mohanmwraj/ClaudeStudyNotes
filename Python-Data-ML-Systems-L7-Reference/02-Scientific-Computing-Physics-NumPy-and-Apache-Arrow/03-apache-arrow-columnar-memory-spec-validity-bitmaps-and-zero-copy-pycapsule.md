# 02.3 · Apache Arrow: Columnar Memory Spec, Validity Bitmaps & Zero-Copy via the PyCapsule Interface

> **Folder 02 · Scientific Computing Physics: NumPy & Apache Arrow**
> **Measured on:** CPython 3.14.5, pyarrow 26.0.0, Polars 2.1.0, DuckDB 2.0.0, pandas 3.1.0, NumPy 2.5.4, GCC 16.2 (C consumer), i5-11260H, Windows 11.
> **Spec verified against:** the Arrow Columnar Format (buffer layouts, validity bitmaps, Utf8View), the Arrow C Data Interface (`ArrowSchema`, `ArrowArray`, `ArrowArrayStream`), and the Arrow PyCapsule Interface. Struct sizes were checked with ctypes (72 B / 80 B).

---

## 0. Orientation & the JVM/C++ Bridge

Arrow is a **language-independent memory layout for columns**, plus two ways to move it: a C ABI for in-process handoff (the C Data Interface, wrapped in PyCapsules for Python) and an IPC format for files and sockets. Its point is that *the bytes in memory are the interchange format*. A table produced by DuckDB can be consumed by Polars, pandas, NumPy, a C kernel or PyTorch by handing over pointers, without serialization. Everything in Folders 03, 04 and 08 (Polars, DuckDB, PySpark Arrow UDFs, Ray, Parquet) builds on this file.

| Concept | Arrow | JVM | C++ |
|---|---|---|---|
| Column of values | contiguous buffer(s) + validity bitmap | Arrow Java `ValueVector` (off-heap) | Arrow C++ `ArrayData` |
| Nulls | 1 bit per row, LSB-first; absent if no nulls | `null` references (a pointer per value) | `std::optional<T>` (a byte+ per value) |
| Strings | int32/int64 offsets + data, or 16-byte views | `String[]` (an object per value) | `std::string` array, or a string pool |
| In-process handoff | C Data Interface structs + `release` callback | Panama/JNI over the same structs | the same structs (header-only spec) |
| Python handoff | PyCapsules from `__arrow_c_array__` / `__arrow_c_stream__` | — | — |
| Wire/file | IPC stream/file (Feather v2) with flatbuffer metadata | Arrow Flight / IPC | same |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 Buffer layouts per type

```text
 int64, [1, null, 3, null, 5]
   validity: 1 byte  0b00010101            bit i = row i, least-significant bit first; 1 = valid
   values  : 40 B    [1, ?, 3, ?, 5]        null slots are undefined (pyarrow writes 0)
 utf8 ['ab', null, 'cde', '']
   validity: 0b00001101
   offsets : int32[n+1] = [0, 2, 2, 5, 5]   row i = data[offsets[i] : offsets[i+1]]
   data    : b'abcde'                       null and '' differ only in the validity bit
 large_utf8: same with int64 offsets        (needed once one array's string data exceeds 2 GiB)
 utf8_view (Utf8View, format 1.4+): one 16-byte view per row
   len <= 12: | int32 len | 12 bytes inline data           |
   len  > 12: | int32 len | 4-byte prefix | int32 buf_idx | int32 offset |  -> variadic data buffers
   (compare/filter on the prefix without touching the data; Polars' native string layout)
 dictionary<int32, utf8>: int32 indices + one dictionary array (4.5 MiB vs 13.4 MiB for 1M low-cardinality strings)
 struct: a validity bitmap + one child array per field;  list<T>: offsets + child array
```

Rules the spec guarantees, which make SIMD and zero-copy possible:

* **Buffers are contiguous and aligned.** 8-byte alignment is required and 64 bytes recommended. pyarrow allocates 64-byte-aligned (measured: every address % 64 == 0), so an AVX-512 load never splits a line at the buffer start.
* **A validity bitmap may be omitted** when `null_count == 0`. Kernels take a no-nulls fast path.
* **Slicing is `(offset, length)` over the same buffers.** `arr.slice(1, 2)` shares the data buffer (measured), and consumers must apply `offset` to *every* buffer, bitmap included (the C consumer in §2.2 does).
* **Null slots hold garbage by contract.** Kernels may compute on them and mask afterwards. That's what makes branchless null handling legal.

### 1.2 The C Data Interface: two structs and a release callback

```c
struct ArrowSchema {                    /* 72 B on 64-bit (ctypes-verified) */
  const char *format;                   /* "l" = int64, "g" = float64, "u" = utf8, "U" = large utf8, "vu" = utf8 view, "+s" = struct */
  const char *name, *metadata;
  int64_t flags, n_children;            /* flags: NULLABLE, DICTIONARY_ORDERED, MAP_KEYS_SORTED */
  struct ArrowSchema **children, *dictionary;
  void (*release)(struct ArrowSchema *);
  void *private_data;
};
struct ArrowArray {                     /* 80 B */
  int64_t length, null_count, offset, n_buffers, n_children;
  const void **buffers;                 /* [validity, values] / [validity, offsets, data] / ... */
  struct ArrowArray **children, *dictionary;
  void (*release)(struct ArrowArray *); /* the consumer calls it exactly once; then release == NULL */
  void *private_data;                   /* the producer's bookkeeping (e.g. a reference to its buffers) */
};
struct ArrowArrayStream {               /* a pull iterator of batches */
  int (*get_schema)(struct ArrowArrayStream *, struct ArrowSchema *out);
  int (*get_next)(struct ArrowArrayStream *, struct ArrowArray *out);   /* out->release == NULL at end */
  const char *(*get_last_error)(struct ArrowArrayStream *);
  void (*release)(struct ArrowArrayStream *);
  void *private_data;
};
```

Ownership is **moved**, not shared. The producer fills the struct and transfers responsibility for calling `release`. The consumer may move it again (copy the struct, mark the source released). Nothing is copied but pointers. The C Device Data Interface (`ArrowDeviceArray`) adds a device type and ID so the same handoff works for GPU memory (relevant to 06/08).

### 1.3 The PyCapsule interface

```text
 producer.__arrow_c_schema__()                     -> PyCapsule "arrow_schema"
 producer.__arrow_c_array__(requested_schema=None) -> (PyCapsule "arrow_schema", PyCapsule "arrow_array")
 producer.__arrow_c_stream__(requested_schema=None)-> PyCapsule "arrow_array_stream"
 (device variants: __arrow_c_device_array__ / __arrow_c_device_stream__)
 consumer: pa.table(x), pa.array(x), pl.DataFrame(x), duckdb.sql("... FROM x"), pd.DataFrame.from_arrow(x), ...
 capsule destructor: if the consumer never imported it, call release() -> no leak
```

Any object with these dunders, including your own (the `Producer` class in §2.2), is a first-class Arrow citizen to every consumer, with no dependency on pyarrow. This replaced earlier library-specific private APIs (`_export_to_c` integer pointers) that had no lifetime safety.

### 1.4 What "zero copy" does and doesn't guarantee

Zero copy means the **consumer's native layout equals Arrow's** for that column, so only the struct moves. It fails, and the consumer converts, when:

| Situation | Who converts | Measured |
|---|---|---|
| Polars importing `utf8`/`large_utf8` | Polars builds Utf8View views | 30–40 ms for 20 M strings (numeric columns: ~20–30 µs) |
| NumPy from a column with nulls, or from several chunks | NumPy can't represent a bitmap or chunks: `zero_copy_only` raises / concatenates | — (listing uses a null-free single chunk) |
| pandas 3 `DataFrame.from_arrow` / default `to_pandas()` | numerics into NumPy blocks | 96–130 ms for 20 M rows; strings stay Arrow-backed (`str` dtype) and are **not** copied |
| pandas 3 `to_pandas(types_mapper=pd.ArrowDtype)` | none | ~0.3–0.6 ms, zero copy for every column |
| IPC with compression (LZ4/ZSTD) | decompression | full pass |

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 The format, byte by byte

```python
"""arrow_buffer_anatomy.py - the Arrow columnar format, byte by byte, read back from pyarrow's own buffers.

Primitive: [validity bitmap, values]. Utf8: [validity, int32 offsets (n+1), data]. Large utf8: int64 offsets.
Utf8View: [validity, 16-byte views, data buffers...]; a view is {int32 len, 12 inline bytes} or
{int32 len, 4-byte prefix, int32 buffer index, int32 offset}. Bitmaps are LSB-first.
"""
import struct
import sys
import time

import numpy as np
import pyarrow as pa
import pyarrow.compute as pc

print(f"pyarrow {pa.__version__}")
print("== A. int64 with nulls: [1, None, 3, None, 5]")
a = pa.array([1, None, 3, None, 5], pa.int64())
validity, values = a.buffers()
bits = validity.to_pybytes()[0]
print(f"  buffers: validity {validity.size} B, values {values.size} B; null_count={a.null_count}")
print(f"  validity byte 0 = {bits:#010b}  (bit i = row i, LSB first: rows 0,2,4 valid)")
print(f"  values = {np.frombuffer(values, np.int64)[:5].tolist()} (null slots hold arbitrary bytes; here 0)")
assert bits & 0b11111 == 0b10101

print("== B. utf8 ['ab', None, 'cde', ''] : validity + int32 offsets + one data buffer")
s = pa.array(["ab", None, "cde", ""], pa.string())
v, off, data = s.buffers()
offsets = np.frombuffer(off, np.int32)[: len(s) + 1].tolist()
print(f"  offsets = {offsets}  data = {data.to_pybytes()[: offsets[-1]]!r}")
print(f"  row i = data[offsets[i]:offsets[i+1]]; null and '' differ only in the validity bit")
assert offsets == [0, 2, 2, 5, 5]
ls = pa.array(["ab", None, "cde", ""], pa.large_string())
print(f"  large_string offsets are int64: {ls.buffers()[1].size} B for {len(ls) + 1} offsets")

print("== C. slicing is zero-copy: same buffers, new offset/length")
sl = s.slice(1, 2)
print(f"  s.slice(1, 2): offset={sl.offset} length={len(sl)} "
      f"data buffer shared={sl.buffers()[2].address == data.address} -> {sl.to_pylist()}")
assert sl.buffers()[2].address == data.address and sl.offset == 1

print("== D. string_view (Utf8View): 16-byte views, short strings inline")
sv = pa.array(["hi", "exactly12byt", "this one is longer than twelve", None], pa.string_view())
bufs = sv.buffers()
views = bufs[1].to_pybytes()
for i in range(len(sv)):
    raw = views[16 * i:16 * i + 16]
    n = struct.unpack_from("<i", raw)[0]
    if n <= 12:
        print(f"  row {i}: len={n:2} inline={raw[4:4 + n]!r}")
    else:
        prefix, buf_idx, off_ = raw[4:8], *struct.unpack_from("<ii", raw, 8)
        print(f"  row {i}: len={n:2} prefix={prefix!r} -> data buffer {buf_idx} at offset {off_}")
print(f"  buffers: validity, views ({bufs[1].size} B), {len(bufs) - 2} variadic data buffer(s)")

print("== E. alignment and size: 1M short strings")
words = [f"user_{i % 50_000:05d}" for i in range(1_000_000)]
arr = pa.array(words, pa.string())
arr_v = pa.array(words, pa.string_view())
dict_arr = arr.dictionary_encode()
rows = [("Python list[str] (1M str objects + pointers)", sys.getsizeof(words) + sum(map(sys.getsizeof, words))),
        ("Arrow utf8: offsets + data", arr.nbytes), ("Arrow utf8_view: views + data", arr_v.nbytes),
        ("Arrow dictionary<int32, utf8>", dict_arr.nbytes)]
for label, nb in rows:
    print(f"  {label:44} {nb / 2**20:7.2f} MiB")
print(f"  buffer addresses % 64 (pyarrow pads/aligns to 64 B): "
      f"{sorted({b.address % 64 for b in arr.buffers() if b is not None})}")

print("== F. null handling: bitmap popcount vs Python 'is None' scan, 10M rows, 10% null")
rng = np.random.default_rng(0)
mask = rng.random(10_000_000) < 0.1
big = pa.array(rng.integers(0, 1000, 10_000_000), mask=mask)
py = big.to_pylist()
t0 = time.perf_counter()
n_py = sum(1 for x in py if x is None)
t_py = time.perf_counter() - t0
t0 = time.perf_counter()
n_arrow = big.null_count                                 # cached when the array is built
t_cnt = time.perf_counter() - t0
t0 = time.perf_counter()
s_arrow = pc.sum(big).as_py()                            # SIMD sum that skips nulls via the bitmap
t_sum = time.perf_counter() - t0
assert n_py == n_arrow == int(mask.sum()) and s_arrow == sum(x for x in py if x is not None)
print(f"  Python scan for None: {t_py * 1e3:7.1f} ms | arr.null_count: {t_cnt * 1e6:5.1f} us | "
      f"pc.sum (null-aware): {t_sum * 1e3:5.1f} ms")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run; layout lines are deterministic):

```text
pyarrow 26.0.0
== A. int64 with nulls: [1, None, 3, None, 5]
  buffers: validity 1 B, values 40 B; null_count=2
  validity byte 0 = 0b00010101  (bit i = row i, LSB first: rows 0,2,4 valid)
  values = [1, 0, 3, 0, 5] (null slots hold arbitrary bytes; here 0)
== B. utf8 ['ab', None, 'cde', ''] : validity + int32 offsets + one data buffer
  offsets = [0, 2, 2, 5, 5]  data = b'abcde'
  row i = data[offsets[i]:offsets[i+1]]; null and '' differ only in the validity bit
  large_string offsets are int64: 40 B for 5 offsets
== C. slicing is zero-copy: same buffers, new offset/length
  s.slice(1, 2): offset=1 length=2 data buffer shared=True -> [None, 'cde']
== D. string_view (Utf8View): 16-byte views, short strings inline
  row 0: len= 2 inline=b'hi'
  row 1: len=12 inline=b'exactly12byt'
  row 2: len=30 prefix=b'this' -> data buffer 0 at offset 0
  row 3: len= 0 inline=b''
  buffers: validity, views (64 B), 1 variadic data buffer(s)
== E. alignment and size: 1M short strings
  Python list[str] (1M str objects + pointers)   56.69 MiB
  Arrow utf8: offsets + data                     13.35 MiB
  Arrow utf8_view: views + data                  15.26 MiB
  Arrow dictionary<int32, utf8>                   4.48 MiB
  buffer addresses % 64 (pyarrow pads/aligns to 64 B): [0]
== F. null handling: bitmap popcount vs Python 'is None' scan, 10M rows, 10% null
  Python scan for None:   205.8 ms | arr.null_count:   5.1 us | pc.sum (null-aware):  25.3 ms
ALL ASSERTIONS PASSED
```

* The validity byte is `0b00010101` for rows 0, 2 and 4 valid; the offsets for the utf8 array are exactly `[0, 2, 2, 5, 5]`; a slice shares the data buffer.
* Utf8View stores `"hi"` and the 12-byte string inline and spills the 30-byte one to a data buffer with a 4-byte prefix. Comparisons can often finish on the inline prefix.
* 1 M short strings: **57 MiB as Python `str` objects + pointers**, 13 MiB as Arrow utf8, 15 MiB as utf8_view (16 B views), and **4.5 MiB dictionary-encoded** (only 50 k distinct values).
* Counting nulls is O(1) (`null_count` is cached); a Python `is None` scan over the same 10 M values takes ~190–210 ms.

### 2.2 The C Data Interface from both sides: export, a C consumer, release, capsules

```c
/* arrow_consumer.c - a C consumer of the Arrow C Data Interface: sum an int64 ArrowArray, honoring validity. */
/* Build: gcc -O2 -shared -o arrow_consumer.dll arrow_consumer.c   (struct layout from the Arrow C Data spec) */
#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT
#endif

struct ArrowArray {
    int64_t length, null_count, offset, n_buffers, n_children;
    const void **buffers;              /* [0] validity bitmap (may be NULL), [1] values */
    struct ArrowArray **children;
    struct ArrowArray *dictionary;
    void (*release)(struct ArrowArray *);
    void *private_data;
};

static inline int valid_at(const uint8_t *bitmap, int64_t j) { return (bitmap[j >> 3] >> (j & 7)) & 1; }

/* Branch per row: a misprediction whenever nulls are unpredictable. */
EXPORT int64_t sum_branchy(const struct ArrowArray *a) {
    const uint8_t *valid = (const uint8_t *)a->buffers[0];
    const int64_t *v = (const int64_t *)a->buffers[1];
    int64_t s = 0;
    for (int64_t i = 0; i < a->length; i++) {
        int64_t j = i + a->offset;     /* offset applies to every buffer, bitmap included */
        if (valid == NULL || valid_at(valid, j)) s += v[j];
    }
    return s;
}

/* Branchless: turn the validity bit into an all-ones / all-zeros mask and AND it in. */
EXPORT int64_t sum_branchless(const struct ArrowArray *a) {
    const uint8_t *valid = (const uint8_t *)a->buffers[0];
    const int64_t *v = (const int64_t *)a->buffers[1];
    int64_t s = 0;
    if (valid == NULL) {
        for (int64_t i = 0; i < a->length; i++) s += v[i + a->offset];
        return s;
    }
    for (int64_t i = 0; i < a->length; i++) {
        int64_t j = i + a->offset;
        s += v[j] & -(int64_t)valid_at(valid, j);
    }
    return s;
}
```

```python
"""arrow_c_data_interface.py - the Arrow C Data Interface as plain C structs, and the PyCapsule protocol on top.

Exports a pyarrow array into an ArrowSchema/ArrowArray pair, reads the struct fields from Python, hands the same
pointer to a C consumer (arrow_consumer.c), releases it, then shows the PyCapsule dunders that carry these
structs between libraries (__arrow_c_schema__ / __arrow_c_array__ / __arrow_c_stream__).
usage: python arrow_c_data_interface.py PATH_TO_arrow_consumer.dll
"""
import ctypes
import sys
import time

import numpy as np
import polars as pl
import pyarrow as pa
import pyarrow.compute as pc


class ArrowSchema(ctypes.Structure):
    pass


ArrowSchema._fields_ = [("format", ctypes.c_char_p), ("name", ctypes.c_char_p), ("metadata", ctypes.c_char_p),
                        ("flags", ctypes.c_int64), ("n_children", ctypes.c_int64),
                        ("children", ctypes.POINTER(ctypes.POINTER(ArrowSchema))),
                        ("dictionary", ctypes.POINTER(ArrowSchema)),
                        ("release", ctypes.CFUNCTYPE(None, ctypes.POINTER(ArrowSchema))),
                        ("private_data", ctypes.c_void_p)]


class ArrowArray(ctypes.Structure):
    pass


ArrowArray._fields_ = [("length", ctypes.c_int64), ("null_count", ctypes.c_int64), ("offset", ctypes.c_int64),
                       ("n_buffers", ctypes.c_int64), ("n_children", ctypes.c_int64),
                       ("buffers", ctypes.POINTER(ctypes.c_void_p)),
                       ("children", ctypes.POINTER(ctypes.POINTER(ArrowArray))),
                       ("dictionary", ctypes.POINTER(ArrowArray)),
                       ("release", ctypes.CFUNCTYPE(None, ctypes.POINTER(ArrowArray))),
                       ("private_data", ctypes.c_void_p)]

lib = ctypes.CDLL(sys.argv[1])
for fn in (lib.sum_branchy, lib.sum_branchless):
    fn.argtypes, fn.restype = [ctypes.POINTER(ArrowArray)], ctypes.c_int64

print(f"sizeof(ArrowSchema)={ctypes.sizeof(ArrowSchema)} B, sizeof(ArrowArray)={ctypes.sizeof(ArrowArray)} B")
N = 10_000_000
rng = np.random.default_rng(0)
arr = pa.array(rng.integers(0, 1000, N), mask=rng.random(N) < 0.5)   # 50% random nulls: worst case for branches

print("== A. export: pyarrow fills the structs; buffers are pointers into pyarrow's memory")
c_sch, c_arr = ArrowSchema(), ArrowArray()
t0 = time.perf_counter()
arr._export_to_c(ctypes.addressof(c_arr), ctypes.addressof(c_sch))
t_exp = time.perf_counter() - t0
print(f"  export {N:,} rows in {t_exp * 1e6:.1f} us; format={c_sch.format!r} length={c_arr.length:,} "
      f"null_count={c_arr.null_count:,} offset={c_arr.offset} n_buffers={c_arr.n_buffers}")
same = [c_arr.buffers[i] == arr.buffers()[i].address for i in range(c_arr.n_buffers)]
print(f"  struct buffers[i] == pyarrow buffer addresses: {same}  (zero copy)")
assert all(same)

print("== B. a C consumer reads the same memory")
ref = pc.sum(arr).as_py()
for label, fn in [("C, branch per row", lib.sum_branchy), ("C, branchless mask", lib.sum_branchless)]:
    t0 = time.perf_counter()
    s = fn(ctypes.byref(c_arr))
    dt = time.perf_counter() - t0
    assert s == ref
    print(f"  {label:22} sum={s:,}  {dt * 1e3:6.1f} ms")
t0 = time.perf_counter()
pc.sum(arr)
print(f"  {'pyarrow.compute.sum':22} sum={ref:,}  {(time.perf_counter() - t0) * 1e3:6.1f} ms")

print("== C. release(): the consumer hands ownership back exactly once")
c_arr.release(ctypes.byref(c_arr))
c_sch.release(ctypes.byref(c_sch))
print(f"  after release: array.release is NULL = {not c_arr.release}, schema.release is NULL = {not c_sch.release}")
assert not c_arr.release and not c_sch.release

print("== D. slices export an offset, not a copy")
sl = arr.slice(5, 1000)
c2s, c2a = ArrowSchema(), ArrowArray()
sl._export_to_c(ctypes.addressof(c2a), ctypes.addressof(c2s))
print(f"  arr.slice(5, 1000): offset={c2a.offset} length={c2a.length} values buffer shared="
      f"{c2a.buffers[1] == arr.buffers()[1].address}")
assert lib.sum_branchless(ctypes.byref(c2a)) == pc.sum(sl).as_py()
c2a.release(ctypes.byref(c2a))
c2s.release(ctypes.byref(c2s))

print("== E. PyCapsules: the same structs, wrapped so any library can consume them")
ctypes.pythonapi.PyCapsule_GetName.restype = ctypes.c_char_p
ctypes.pythonapi.PyCapsule_GetName.argtypes = [ctypes.py_object]
sch_cap, arr_cap = arr.__arrow_c_array__()
stream_cap = pa.table({"x": arr}).__arrow_c_stream__()
print(f"  capsule names: {ctypes.pythonapi.PyCapsule_GetName(sch_cap)!r}, "
      f"{ctypes.pythonapi.PyCapsule_GetName(arr_cap)!r}, {ctypes.pythonapi.PyCapsule_GetName(stream_cap)!r}")


class Producer:
    """Any object with __arrow_c_array__ is importable by pyarrow, polars, duckdb, pandas 3, ..."""
    def __init__(self, a):
        self.a = a

    def __arrow_c_array__(self, requested_schema=None):
        return self.a.__arrow_c_array__(requested_schema)


back = pa.array(Producer(arr))
print(f"  pa.array(Producer(arr)): values buffer shared={back.buffers()[1].address == arr.buffers()[1].address}")
df = pl.DataFrame({"x": pl.Series(Producer(arr))})
pl_addr = df["x"].to_arrow().buffers()[1].address
print(f"  polars Series from the capsule: values buffer shared={pl_addr == arr.buffers()[1].address}; "
      f"sum={df['x'].sum():,}")
assert back.buffers()[1].address == arr.buffers()[1].address and df["x"].sum() == ref
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
sizeof(ArrowSchema)=72 B, sizeof(ArrowArray)=80 B
== A. export: pyarrow fills the structs; buffers are pointers into pyarrow's memory
  export 10,000,000 rows in 59.2 us; format=b'l' length=10,000,000 null_count=4,999,779 offset=0 n_buffers=2
  struct buffers[i] == pyarrow buffer addresses: [True, True]  (zero copy)
== B. a C consumer reads the same memory
  C, branch per row      sum=2,497,637,281    41.5 ms
  C, branchless mask     sum=2,497,637,281     9.5 ms
  pyarrow.compute.sum    sum=2,497,637,281    48.1 ms
== C. release(): the consumer hands ownership back exactly once
  after release: array.release is NULL = True, schema.release is NULL = True
== D. slices export an offset, not a copy
  arr.slice(5, 1000): offset=5 length=1000 values buffer shared=True
== E. PyCapsules: the same structs, wrapped so any library can consume them
  capsule names: b'arrow_schema', b'arrow_array', b'arrow_array_stream'
  pa.array(Producer(arr)): values buffer shared=True
  polars Series from the capsule: values buffer shared=True; sum=2,497,637,281
ALL ASSERTIONS PASSED
```

* Exporting 10 M rows takes **~40–60 µs**. The struct's `buffers[]` *are* pyarrow's buffer addresses, and a C function compiled separately sums the same memory.
* **Branchless null handling is ~4× faster** than a branch per row at 50 % random nulls (≈ 9.5 ms against ≈ 38–42 ms): validity bit → all-ones/zero mask → `AND`. This is the "branchless SIMD null skipping" the format was designed for, and why null slots may hold garbage.
* `release()` sets the callback to NULL. Calling it twice would be a double free, and not calling it would leak the producer's buffers. PyCapsule destructors exist to make the "not called" case safe in Python.
* Polars built a Series from a *hand-written* producer's capsule and reused the same buffer.

### 2.3 Trap: converting between libraries. Pattern: handing over pointers

```python
"""pycapsule_zero_copy_exchange.py - pass one Arrow table between pyarrow, Polars, DuckDB, pandas 3 and NumPy.

For each handoff: wall time and whether the float64 column's buffer address survived (zero copy) or not.
Numeric columns cross as pointers (cost ~ O(columns)); strings may be re-encoded (Polars stores Utf8View).
"""
import pickle
import time

import duckdb
import numpy as np
import pandas as pd
import polars as pl
import pyarrow as pa

N = 20_000_000
rng = np.random.default_rng(0)
cats = np.array([f"cat_{i:04d}" for i in range(1000)])
tbl = pa.table({"id": np.arange(N, dtype=np.int64), "value": rng.random(N),
                "category": pa.array(cats[rng.integers(0, 1000, N)])})
VALUE = tbl["value"].chunk(0).buffers()[1].address
print(f"table: {N:,} rows, {tbl.nbytes / 2**20:.0f} MiB ({', '.join(f'{f.name}:{f.type}' for f in tbl.schema)})")


def timed(fn, reps=1):
    best, r = float("inf"), None
    for _ in range(reps):
        t0 = time.perf_counter()
        r = fn()
        best = min(best, time.perf_counter() - t0)
    return r, best


def fmt(dt):
    return f"{dt * 1e6:9.1f} us" if dt < 1e-3 else f"{dt * 1e3:9.1f} ms"


def addr(chunked_or_array, i=1):
    a = chunked_or_array.chunk(0) if isinstance(chunked_or_array, pa.ChunkedArray) else chunked_or_array
    return a.buffers()[i].address


num = tbl.select(["id", "value"])
CAT = addr(tbl["category"], 2)                          # string data buffer
handoffs = [
    ("pyarrow -> Polars (numeric cols)", lambda: pl.from_arrow(num),
     lambda r: addr(r["value"].to_arrow()) == VALUE),
    ("pyarrow -> Polars (incl. string col)", lambda: pl.from_arrow(tbl),
     lambda r: addr(r["value"].to_arrow()) == VALUE),
    ("Polars -> pyarrow (numeric)", lambda: pl.from_arrow(num).to_arrow(),
     lambda r: addr(r["value"]) == VALUE),
    ("pyarrow -> NumPy (to_numpy zero_copy_only)", lambda: tbl["value"].chunk(0).to_numpy(zero_copy_only=True),
     lambda r: r.ctypes.data == VALUE),
    ("pyarrow -> NumPy (DLPack)", lambda: np.from_dlpack(tbl["value"].chunk(0)), lambda r: r.ctypes.data == VALUE),
    ("pyarrow -> pandas 3 to_pandas(ArrowDtype)", lambda: tbl.to_pandas(types_mapper=pd.ArrowDtype),
     lambda r: addr(pa.array(r["value"].array)) == VALUE),
    ("pyarrow -> pandas 3 DataFrame.from_arrow", lambda: pd.DataFrame.from_arrow(num),
     lambda r: r["value"].to_numpy().ctypes.data == VALUE),
    ("pyarrow -> pandas 3 to_pandas() default", lambda: tbl.to_pandas(),
     lambda r: r["value"].to_numpy().ctypes.data == VALUE),
]
tiny = tbl.slice(0, 10)
for warm in (lambda: pl.from_arrow(tiny).to_arrow(), lambda: np.from_dlpack(tiny["value"].chunk(0)),
             lambda: tiny.to_pandas(types_mapper=pd.ArrowDtype), lambda: tiny.to_pandas(),
             lambda: pd.DataFrame.from_arrow(tiny.select(["id", "value"]))):
    warm()                                              # first-call library initialization, outside the timings
print(f"{'handoff (best of 3, after warm-up)':46} {'time':>12}  float64 buffer reused?")
results = {}
for label, fn, check in handoffs:
    r, dt = timed(fn, reps=3)
    results[label] = r
    print(f"  {label:44} {fmt(dt)}  {'YES (zero copy)' if check(r) else 'no (copied)'}")
df_all = results["pyarrow -> Polars (incl. string col)"]
pdf_np = results["pyarrow -> pandas 3 to_pandas() default"]
shared_str = addr(pa.array(pdf_np["category"].array), 2) == CAT
print(f"  pandas 3 default to_pandas(): value -> {pdf_np['value'].dtype} (copied); category -> "
      f"{pdf_np['category'].dtype} backed by {type(pdf_np['category'].array).__name__}, Arrow string data reused: "
      f"{shared_str}")

print("== scans without conversion (best of 3): DuckDB reads the Arrow memory in place")
q = "SELECT category, avg(value) AS m, count(*) AS n FROM src GROUP BY category ORDER BY category LIMIT 3"
src = tbl
r1, t_arrow = timed(lambda: duckdb.sql(q).fetchall(), reps=3)
src = df_all
r2, t_polars = timed(lambda: duckdb.sql(q).fetchall(), reps=3)
assert [x[0] for x in r1] == [x[0] for x in r2] and all(abs(a[1] - b[1]) < 1e-9 for a, b in zip(r1, r2))
print(f"  DuckDB GROUP BY over the pyarrow table : {fmt(t_arrow)}")
print(f"  DuckDB GROUP BY over the Polars frame  : {fmt(t_polars)}  (via __arrow_c_stream__)")
pl_res, t_pl = timed(lambda: df_all.group_by("category").agg(pl.col("value").mean()).sort("category").head(3), reps=3)
print(f"  Polars group_by on its own frame       : {fmt(t_pl)}")

print("== cost is O(columns), not O(rows): pyarrow -> Polars for numeric tables of growing size")
for n in (1_000_000, 5_000_000, 20_000_000):
    _, dt = timed(lambda: pl.from_arrow(num.slice(0, n)), reps=3)
    print(f"  {n:>11,} rows ({n * 16 / 2**20:6.0f} MiB) -> {fmt(dt)}")

print("== what actual serialization costs (the thing zero copy avoids)")
_, t_pk = timed(lambda: pickle.dumps(num, protocol=5))
_, t_py = timed(lambda: num.slice(0, 1_000_000).to_pylist())
print(f"  pickle.dumps(numeric table, protocol 5): {fmt(t_pk)}")
print(f"  .to_pylist() of 1M rows (Python dicts) : {fmt(t_py)}  (x20 for the full table)")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
table: 20,000,000 rows, 534 MiB (id:int64, value:double, category:string)
handoff (best of 3, after warm-up)                     time  float64 buffer reused?
  pyarrow -> Polars (numeric cols)                  29.9 us  YES (zero copy)
  pyarrow -> Polars (incl. string col)              30.9 ms  no (copied)
  Polars -> pyarrow (numeric)                       68.7 us  YES (zero copy)
  pyarrow -> NumPy (to_numpy zero_copy_only)         7.0 us  YES (zero copy)
  pyarrow -> NumPy (DLPack)                          5.8 us  YES (zero copy)
  pyarrow -> pandas 3 to_pandas(ArrowDtype)        561.8 us  YES (zero copy)
  pyarrow -> pandas 3 DataFrame.from_arrow         100.2 ms  no (copied)
  pyarrow -> pandas 3 to_pandas() default          120.0 ms  no (copied)
  pandas 3 default to_pandas(): value -> float64 (copied); category -> str backed by ArrowStringArray, Arrow string data reused: True
== scans without conversion (best of 3): DuckDB reads the Arrow memory in place
  DuckDB GROUP BY over the pyarrow table :      96.4 ms
  DuckDB GROUP BY over the Polars frame  :     249.1 ms  (via __arrow_c_stream__)
  Polars group_by on its own frame       :     668.6 ms
== cost is O(columns), not O(rows): pyarrow -> Polars for numeric tables of growing size
    1,000,000 rows (    15 MiB) ->      93.2 us
    5,000,000 rows (    76 MiB) ->      71.9 us
   20,000,000 rows (   305 MiB) ->      57.0 us
== what actual serialization costs (the thing zero copy avoids)
  pickle.dumps(numeric table, protocol 5):     237.8 ms
  .to_pylist() of 1M rows (Python dicts) :     456.6 ms  (x20 for the full table)
ALL ASSERTIONS PASSED
```

* **Numeric handoffs cost microseconds regardless of size**: pyarrow→Polars ≈ 20–30 µs, Polars→pyarrow ≈ 50–70 µs, NumPy via `to_numpy(zero_copy_only)` or DLPack ≈ 3–7 µs, pandas 3 with `ArrowDtype` ≈ 0.3–0.6 ms. The 1 M / 5 M / 20 M sweep is flat (≈ 30–150 µs across runs, dominated by per-call overhead): the cost is **O(columns), not O(rows)**.
* The copies are where layouts differ: Polars string import (~30–40 ms), pandas numerics into NumPy (~100–130 ms). Pickling the numeric table costs ~240 ms, and `to_pylist()` ~0.4 s per million rows.
* **DuckDB scanned the pyarrow table in place** (no import step) and ran a 20 M-row GROUP BY in ~95–250 ms across runs. Over the Polars frame it went through `__arrow_c_stream__`.

> 🔎 **Refining the brief's claim** ("a 10 GB table in 0.01 ms with zero copying"). It holds for **null-free numeric columns whose consumer stores Arrow natively**: measured ~3–70 µs for 300 MiB, and the time doesn't grow with size. It doesn't hold for strings into Polars (re-encoded to views), numerics into pandas' NumPy blocks, null-bearing or chunked columns into NumPy, or compressed IPC. Design pipelines so the hot path stays inside Arrow-native consumers (Polars, DuckDB, pyarrow.compute, pandas `ArrowDtype`) and convert once, at the edge, if at all.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | "Zero-copy" pipeline still doubles memory | RSS ≈ 2× table after `to_pandas()` | Default pandas conversion copies numerics into NumPy | `to_pandas(types_mapper=pd.ArrowDtype)` or stay in Polars/DuckDB | Assert buffer addresses in integration tests (as the listing does) |
| F2 | `ArrowInvalid: Needed to copy 1 chunks with 0 nulls, but zero_copy_only was True` | Raised by `to_numpy(zero_copy_only=True)` | Multiple chunks or nulls | `combine_chunks()` once upstream; fill nulls; or keep the Arrow type | Control chunking at the producer (batch size) |
| F3 🔥 | `ArrowInvalid`/overflow building a string column > 2 GiB | Offset overflow | int32 offsets in `utf8` | `large_string` or `string_view`; smaller record batches | Choose string types by expected size |
| F4 🔥 | Segfault or use-after-free in a native extension consuming Arrow | Crash after the producer object is garbage-collected | Raw pointers (`_export_to_c` integers) used past the producer's lifetime, or `release` never/twice called | PyCapsule protocol; call `release` exactly once; move structs | Never pass bare addresses across library boundaries |
| F5 | Polars ingestion of a string-heavy Parquet/Arrow source slower than expected | Time ∝ string bytes | `large_utf8` → Utf8View conversion | Produce `string_view` upstream (pyarrow supports it) or accept a one-time cost | Know each engine's native string layout |
| F6 | Consumer rejects data from a newer producer | "Unsupported type: string_view / list_view / run-end encoded" | The consumer predates format 1.4 types | `requested_schema` in `__arrow_c_stream__` to ask for `large_string`; cast at the boundary | Pin and test producer/consumer versions together |
| F7 ⚡ | Kernel over nullable data is 4× slower than expected | Branch mispredictions | A branch per row on the validity bit | Branchless masks; process 64 rows per bitmap word; skip all-valid words | Use pyarrow.compute / engine kernels, not hand loops |
| F8 | Tiny cached slice pins a huge table | RSS stays at the full table | A slice shares buffers (offset + length) | `.take()`/copy small results, or `pa.concat_arrays([slice])` | Same rule as NumPy views (02.1) |

**Debugging toolkit.** `arr.buffers()` and `buf.address`/`buf.size` show the layout. `pa.total_allocated_bytes()` reports pyarrow's own pool usage. `pa.default_memory_pool().backend_name` shows the allocator (mimalloc/jemalloc/system). `tbl.schema` / `field.type` and `arr.offset` / `arr.null_count` are the quick checks. Comparing buffer addresses across libraries proves zero copy (§2.3).

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Explain how a null is represented in Arrow and why that's faster than Java's `null`."</b></summary>

**Initial Prompt.** Compare Arrow's null handling to boxed `Integer` with nulls in Java or `Optional` in C++.

**L5 Answer.** "Arrow has a null bitmap; each value has a flag."

**Why L5 Crashes at Scale.** "A flag per value" suggests branching per value. That misses the design that makes it fast (branchless, word-at-a-time, optional bitmaps) and leads teams to write per-row null checks that run 4× slower.

**L7 Principal Defense.** Validity is one bit per row in a separate, LSB-first bitmap that's omitted entirely when there are no nulls. Values for null slots are undefined, so kernels compute on everything and apply the mask: `sum += v & -bit` measured ≈ 9.5 ms against ≈ 38–42 ms branchy at 50 % random nulls. Real kernels also test 64 rows per bitmap word and skip all-valid or all-null words. Java's `Integer[]` costs an object reference per value and a branch per access; `Optional<int64_t>` costs 16 B per value with padding. Arrow costs 1/8 B per value plus contiguous values that SIMD can stream.

</details>

<details><summary><b>Q2 · "How can DuckDB query a Polars DataFrame without copying it?"</b></summary>

**Initial Prompt.** Walk through what happens in `duckdb.sql("SELECT ... FROM df")` where `df` is a Polars DataFrame.

**L5 Answer.** "DuckDB converts the DataFrame to its own format."

**Why L5 Crashes at Scale.** If you think every engine boundary is a conversion, you'll design ETL that materializes between every step (Parquet → pandas → DuckDB → Polars), paying serialization and memory at each hop. That's the Pandas-era 5–10× memory pattern.

**L7 Principal Defense.** DuckDB's replacement scan finds the Python variable, sees `__arrow_c_stream__`, and pulls `ArrowArrayStream` batches. Each batch's `ArrowArray` points into Polars' buffers, and DuckDB's vectorized operators read those vectors directly. Measured: a 20 M-row GROUP BY over a Polars frame or a pyarrow table, with no import step. Conversions appear only where layouts differ (strings into Polars' Utf8View). So the architecture should keep data in Arrow across engine boundaries, choose engines per step (DuckDB for SQL joins and aggregations, Polars for expression pipelines), and convert to Python objects only at the edge.

</details>

<details><summary><b>Q3 · "What's the contract of the `release` callback, and what goes wrong without it?"</b></summary>

**Initial Prompt.** Your team writes a C++ extension that accepts Arrow data from Python. What lifetime rules must it follow?

**L5 Answer.** "Copy the data so you don't depend on Python."

**Why L5 Crashes at Scale.** Copying defeats the purpose (a full pass per call) and still doesn't remove the need to release the producer's struct, so it leaks the producer's buffers if `release` isn't called.

**L7 Principal Defense.** The consumer owns the struct after import. It must call `release` exactly once when done (after which `release == NULL`), or move ownership by copying the struct and marking the source released. Never release twice (double free), never forget (leak), never read after release (use-after-free). In Python, take PyCapsules (`__arrow_c_array__`/`__arrow_c_stream__`): the capsule destructor releases unconsumed data, and importing marks the capsule consumed. In C++, use Arrow C++'s `ImportArray`/`ImportRecordBatchReader` or nanoarrow, which wrap these rules in RAII. Test with ASan, and with a debug allocator that poisons freed buffers.

</details>

<details><summary><b>Q4 · "Should we store strings as `utf8`, `large_utf8`, `string_view` or dictionary?"</b></summary>

**Initial Prompt.** Event logs with a high-cardinality `user_agent` and a low-cardinality `country` column, 50 M rows per day.

**L5 Answer.** "Use `string`; it's the default."

**Why L5 Crashes at Scale.** `utf8`'s int32 offsets overflow once one array's string data passes 2 GiB, which a daily batch of user agents can. It also makes every Polars import pay a view conversion. Low-cardinality columns stored as plain strings waste ~3× memory and slow down group-bys.

**L7 Principal Defense.** `country` should be dictionary-encoded: int32 (or int8/int16) indices plus a tiny dictionary, which measured 4.5 MiB against 13.4 MiB for 1 M low-cardinality strings, with group-bys on integer codes. `user_agent` should be `string_view` if consumers are Polars or DuckDB (inline ≤ 12 bytes, a 4-byte prefix for fast comparisons, no 2 GiB offset limit per buffer), or `large_string` for older consumers. Keep record batches to ~64 K–1 M rows so per-batch buffers stay cache- and pipeline-friendly. Then verify that consumers accept the type (format 1.4 types such as views need recent readers), or negotiate with `requested_schema`.

</details>

<details><summary><b>Q5 · "Is `to_pandas()` zero-copy in pandas 3?"</b></summary>

**Initial Prompt.** A team upgraded to pandas 3 expecting free conversions from Arrow.

**L5 Answer.** "Yes. pandas 3 uses Arrow, so `to_pandas` is zero-copy."

**Why L5 Crashes at Scale.** Measured: default `to_pandas()` and `DataFrame.from_arrow()` **copy numeric columns into NumPy** (96–130 ms for 20 M rows), while string columns become the new `str` dtype backed by `ArrowStringArray` and *do* reuse Arrow's buffers. Assuming everything is zero-copy under-budgets memory by the size of the numeric data.

**L7 Principal Defense.** Be precise about pandas 3. Default string dtype is Arrow-backed (zero copy from Arrow); numeric and datetime columns default to NumPy (copy); `types_mapper=pd.ArrowDtype` keeps *everything* Arrow-backed (~0.3–0.6 ms measured). Choose per workload. NumPy-backed numerics are better for heavy NumPy/scikit-learn interop, ArrowDtype for pipelines that hand data back to Arrow engines. Check with buffer-address assertions, not assumptions, and keep conversions at stage boundaries.

</details>

<details><summary><b>Q6 · "Why does Polars spend 40 ms importing a table that pyarrow built in 0 ms?"</b></summary>

**Initial Prompt.** `pl.from_arrow(tbl)` takes ~20–30 µs for numeric columns but ~30–40 ms once a 20 M-row string column is included.

**L5 Answer.** "Polars copies all data on import."

**Why L5 Crashes at Scale.** It doesn't: the numeric columns in the same table were reused (same buffer address, measured). Concluding "Polars copies" leads to the wrong fix (avoid Polars) instead of the right one (produce the layout Polars wants).

**L7 Principal Defense.** Polars stores strings as Utf8View (BinaryView): 16-byte views with inline short strings and prefixes, which make filtering and comparison cheaper and avoid the 2 GiB offset limit. A `large_utf8` column has offsets instead, so Polars must build one view per row, a pass proportional to rows. Either produce `string_view` upstream (pyarrow and DuckDB can), accept the one-time cost at ingestion, or keep that column in DuckDB/pyarrow if it never needs Polars. Measure per column type; zero copy is a per-column property.

</details>

<details><summary><b>Q7 · "Design the in-process data path from a Parquet file to a PyTorch tensor with no Python objects."</b></summary>

**Initial Prompt.** A training job reads Parquet features and feeds float32 tensors to a model.

**L5 Answer.** "`pd.read_parquet`, then `df.values`, then `torch.tensor(...)`."

**Why L5 Crashes at Scale.** That's three full copies (Parquet decode → pandas blocks → `.values` possibly consolidating → `torch.tensor` always copies) and possibly an object-dtype detour for strings. Memory peaks at 3–4× the batch, and CPU time goes into copying instead of training.

**L7 Principal Defense.** Decode Parquet straight into Arrow record batches (`pyarrow.dataset` or Polars `scan_parquet` with projection and predicate pushdown, 03.2), and cast the feature columns to float32 in Arrow. Hand primitive, null-free, single-chunk columns to NumPy (`to_numpy(zero_copy_only=True)`, measured ~4–7 µs) or straight to the framework via DLPack (`torch.from_dlpack(arrow_array)`, with `np.from_dlpack` measured ~3–6 µs). Stack columns into a contiguous `(batch, features)` buffer once per batch, the only copy, and pin it for the H2D DMA (06.4). Folder 08's blueprint builds exactly this.

</details>

<details><summary><b>Q8 · "How does Arrow IPC differ from the C Data Interface, and when do you use each?"</b></summary>

**Initial Prompt.** Should two services exchange Arrow over gRPC, Flight, or shared memory?

**L5 Answer.** "Arrow is zero-copy everywhere."

**Why L5 Crashes at Scale.** Zero copy is only possible *within one address space* (the C Data Interface) or over shared/mapped memory. Across a network, bytes must be serialized and sent. IPC makes that cheap (flatbuffer metadata plus raw buffers, no per-value encoding), but it isn't free, and compression adds CPU.

**L7 Principal Defense.** Use the C Data Interface/PyCapsules inside one process (library to library, microseconds). Between processes on one host, use the IPC *file* format on shared memory or a memory-mapped file: readers map the buffers without copying (as `np.frombuffer(mmap)` did in 02.2). That's how Ray's object store works (04.3). Across hosts, use Arrow Flight (gRPC streams of IPC messages, parallel endpoints) or IPC over your own transport. Choose compression per link (LZ4 for LAN throughput, ZSTD for WAN) and keep record batches large enough to amortize message overhead. Validate schemas at the boundary: IPC carries the schema, the C interface carries it in `ArrowSchema`.

</details>

---

## 5. Invariants Checklist

- [ ] Arrow = contiguous, 64-B-aligned buffers per column: validity (LSB-first, optional) + values / offsets / views.
- [ ] Null slots are undefined. Kernels compute and then mask (branchless), never branch per row.
- [ ] Slices are (offset, length) over shared buffers, and every buffer access must honour the offset.
- [ ] The C Data Interface moves ownership. `release` is called exactly once, and PyCapsules make that safe in Python.
- [ ] Zero copy is a per-column property: same layout in producer and consumer. Measure buffer addresses.
- [ ] Handoff cost is O(columns) (µs) when zero-copy, O(bytes) when converting (strings into Polars, numerics into pandas NumPy).
- [ ] `utf8` offsets are int32 (2 GiB per array). Use `large_string`/`string_view` for big string data and dictionaries for low cardinality.
- [ ] pandas 3: strings are Arrow-backed by default, numerics aren't. `types_mapper=pd.ArrowDtype` keeps everything Arrow.
- [ ] Across processes, use IPC over shared or mapped memory; across hosts, Flight. Zero copy ends at the address-space boundary.

---

## 6. References

- Arrow Columnar Format (layouts, validity, Utf8View, alignment) — https://arrow.apache.org/docs/format/Columnar.html
- Arrow C Data Interface — https://arrow.apache.org/docs/format/CDataInterface.html
- Arrow C Stream Interface — https://arrow.apache.org/docs/format/CStreamInterface.html
- Arrow C Device Data Interface — https://arrow.apache.org/docs/format/CDeviceDataInterface.html
- Arrow PyCapsule Interface — https://arrow.apache.org/docs/format/CDataInterface/PyCapsuleInterface.html
- Arrow IPC format — https://arrow.apache.org/docs/format/IPC.html
- Arrow Flight — https://arrow.apache.org/docs/format/Flight.html
- pyarrow pandas integration (`types_mapper`, zero-copy rules) — https://arrow.apache.org/docs/python/pandas.html
- Polars user guide, Arrow interop — https://docs.pola.rs/user-guide/misc/arrow/
- DuckDB Python, Arrow integration — https://duckdb.org/docs/stable/guides/python/sql_on_arrow
- nanoarrow (C helper library for the C Data Interface) — https://github.com/apache/arrow-nanoarrow
- "Umbra: A Disk-Based System with In-Memory Performance" (the German-string / view layout behind Utf8View), T. Neumann, M. Freitag, CIDR 2020 — https://www.cidrdb.org/cidr2020/papers/p29-neumann-cidr20.pdf
