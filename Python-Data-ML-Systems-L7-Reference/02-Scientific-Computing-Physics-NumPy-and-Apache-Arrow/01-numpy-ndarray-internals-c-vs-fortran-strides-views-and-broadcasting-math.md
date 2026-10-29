# 02.1 · NumPy `ndarray` Internals: C vs Fortran Order, Strides, Views & Broadcasting Math

> **Folder 02 · Scientific Computing Physics: NumPy & Apache Arrow**
> **Measured on:** CPython 3.14.5, NumPy 2.5.4 (PyPI wheel, OpenBLAS), Numba 0.68.1, i5-11260H (6C/12T, 48 KB L1D, 1.25 MB L2 per core, 8 MB L3), 16 GB, Windows 11.
> **Source verified against:** NumPy 2.5.4 public headers `numpy/_core/include/numpy/ndarraytypes.h` (`PyArrayObject_fields`, `NPY_ARRAY_*` flags); NEP 50 (promotion).
> **Tags:** 🔥 production-critical · ⚡ performance lever · 🧊 Java/C++ bridge · ⚠ release-dependent or not executed here.

---

## 0. Orientation & the JVM/C++ Bridge

An `ndarray` is **a small header that describes how to walk a raw buffer**: a pointer, a shape, a stride per axis in *bytes*, a dtype, and flags. Every slice, transpose, broadcast and most reshapes create a *new header over the same buffer* in O(1). Anything that can't be expressed as `data + Σ iₖ·strideₖ` (fancy indexing, boolean masks, reshaping a non-contiguous view) silently allocates and copies. Most NumPy performance work comes down to knowing which side of that line an operation falls on, and what the stride does to the cache.

| Concept | NumPy 2.5 | Java | C++ |
|---|---|---|---|
| Typed contiguous storage | `ndarray` buffer (`char *data`) | `double[]` / off-heap `DoubleBuffer` | `std::vector<double>`, `std::mdspan` storage |
| Multi-dimensional view | header: `nd`, `dimensions[]`, `strides[]` (bytes) | none built in (`double[][]` is an array of arrays) | `std::mdspan` with `layout_stride` (C++23) |
| Row- vs column-major | `order='C'` / `order='F'`, or any strides | n/a | `layout_right` / `layout_left` |
| Slice / transpose | O(1) new header, shares memory | `ByteBuffer.slice()` (1-D only) | `std::submdspan` |
| Broadcasting | stride 0 on virtual axes | none | `layout_stride` with stride 0 |
| Ownership | `base` chain + `OWNDATA` flag | GC | `shared_ptr` owner / non-owning span |
| Element access cost | Python-level `a[i]` boxes a NumPy scalar (~100× a C load) | JIT-inlined load | inline load |

---

## 1. First Principles: C Memory Layout & Execution Architecture

### 1.1 `PyArrayObject_fields` (NumPy 2.5.4 headers, offsets measured)

```text
 off  0  PyObject_HEAD (refcnt, type)         16 B   (absent under Py_TARGET_ABI3T: NumPy 2.5 is abi3t-ready)
 off 16  char *data                           -> first element of THIS view (not necessarily the allocation)
 off 24  int nd                               number of dimensions
 off 32  npy_intp *dimensions                 shape[nd]
 off 40  npy_intp *strides                    strides[nd], in BYTES (may be 0 or negative)
 off 48  PyObject *base                       the object that owns the memory (ndarray, mmap, bytes...)
 off 56  PyArray_Descr *descr                 dtype: kind, itemsize, byte order, fields
 off 64  int flags                            C_CONTIGUOUS 0x1, F_CONTIGUOUS 0x2, OWNDATA 0x4,
                                              ALIGNED 0x100, WRITEABLE 0x400, WRITEBACKIFCOPY 0x2000
 ...     weakreflist, _buffer_info, mem_handler (NEP 49 allocator hook)
 address(a[i0, i1, ..., ik]) = data + i0*strides[0] + i1*strides[1] + ... + ik*strides[k]
```

```text
 a = np.arange(24, dtype=int64).reshape(4, 6)       C order: strides (48, 8)
   buffer (192 B):  [ 0  1  2  3  4  5 | 6  7  8  9 10 11 | 12 ... 17 | 18 ... 23 ]
                      <------ row 0 ---->   48 B per row step, 8 B per column step
 a.T        : same buffer, shape (6, 4), strides (8, 48)       -> F-contiguous
 a[::2, 1:] : data + 8, shape (2, 5), strides (96, 8)           -> neither C nor F contiguous
 broadcast_to(a[0], (1000, 6)): strides (0, 8)                  -> 1000 "rows" that are the same 48 bytes
```

### 1.2 When NumPy must copy

A view is possible iff the requested element order can be expressed by *some* `(data, shape, strides)`. The rules:

| Operation | Result | Why |
|---|---|---|
| basic slicing `a[i:j:k, ...]`, `a.T`, `swapaxes`, `np.broadcast_to`, `a[None]` | **view** | new strides/offset |
| `a.reshape(...)` | view **if** the new shape can be strided over the old layout, else **copy** | `a.T.reshape(-1)` must reorder bytes |
| `a.ravel()` | view if C-contiguous, else copy | `a.flatten()` always copies |
| fancy indexing `a[[0, 2]]`, boolean `a[mask]` | **copy** always | arbitrary gather, no stride describes it |
| `np.ascontiguousarray(x)` | copy iff `x` isn't C-contiguous | layout normalization |
| arithmetic `a * 2 + 1` | **new arrays** for every intermediate | eager evaluation |

⚠ NumPy has no `is_contiguous()`; that's PyTorch (06.1). In NumPy use `a.flags.c_contiguous` / `f_contiguous`, `np.shares_memory(a, b)` for overlap, and `a.base` for ownership.

### 1.3 Stride physics: the cache line is the unit of cost

The hardware moves **64-byte lines**, not elements. With stride 8 B, one line serves 8 float64s. With any stride ≥ 64 B, *every element costs a full line*, and with strides ≥ 4 KiB (a column of a 4096-wide float64 matrix is 32 KiB apart) every access also lands on a different page, stressing the TLB and defeating the L2 streaming prefetcher:

```text
 useful bandwidth = (bytes you use) / (lines touched x 64 B) x (line bandwidth)
 A[:, ::8] reads 1 float64 per line -> 12.5 % of fetched bytes are used -> ~4x slower than contiguous (measured)
 column-major walk of C-order data   -> 10x slower than row-major in the same compiled loop (measured)
```

🧊 This is identical to a Java `double[][]` walked column-first, or C++ `for j: for i: a[i][j]`. NumPy doesn't save you here if *you* write the loop (Numba, Cython, Python). Its own ufuncs and reductions do reorder iteration to the memory order. `A.T[:512].sum()` runs as fast as `A[:, :512].sum()` because NumPy's iterator (`nditer`) sorts axes by stride before looping.

### 1.4 Broadcasting is stride-0 arithmetic

Shapes align from the right, and each dimension must be equal or 1. A dimension of size 1 (or a missing one) is stretched with **stride 0**. No memory is touched to create the view, but **the result of an operation is materialized at the full broadcast shape**. `x[:, None, :] - x[None, :, :]` for N = 50 000 points in 16-D describes 298 GiB, and NumPy will try to allocate every byte of it.

### 1.5 Promotion: NumPy 2's NEP 50

NumPy 2.0 made Python scalars **weak**: `float32_array * 2.5` stays `float32`, while `float32_array * np.float64(2.5)` becomes `float64`. Out-of-range Python integers raise instead of silently up-casting (`uint8_array + 300` → `OverflowError`), but in-range arithmetic still **wraps** (`uint8(255) + 1 == 0`). Every accidental up-cast doubles memory and halves SIMD width (§2.3).

---

## 2. The Slow Pythonic Trap vs. the L7 Production Pattern

### 2.1 Read the header off live arrays: views vs. copies, and what each costs

```python
"""ndarray_anatomy.py - read PyArrayObject_fields off live ndarrays: a view is a new header over the same buffer.

NumPy 2.5 (numpy/_core/include/numpy/ndarraytypes.h): PyObject_HEAD; char *data; int nd; npy_intp *dimensions;
npy_intp *strides; PyObject *base; PyArray_Descr *descr; int flags; PyObject *weakreflist; ...
Element address = data + sum(i_k * strides_k). Views change data/shape/strides; copies change the buffer.
"""
import ctypes
import time

import numpy as np


class PyArrayObject(ctypes.Structure):
    _fields_ = [("ob_refcnt", ctypes.c_ssize_t), ("ob_type", ctypes.c_void_p),
                ("data", ctypes.c_void_p), ("nd", ctypes.c_int),
                ("dimensions", ctypes.POINTER(ctypes.c_ssize_t)), ("strides", ctypes.POINTER(ctypes.c_ssize_t)),
                ("base", ctypes.c_void_p), ("descr", ctypes.c_void_p), ("flags", ctypes.c_int),
                ("weakreflist", ctypes.c_void_p)]


FLAGS = [("C", 0x1), ("F", 0x2), ("OWNDATA", 0x4), ("ALIGNED", 0x100), ("WRITEABLE", 0x400)]


def header(a):
    h = PyArrayObject.from_address(id(a))
    shape = tuple(h.dimensions[i] for i in range(h.nd))
    strides = tuple(h.strides[i] for i in range(h.nd))
    assert (shape, strides, h.data) == (a.shape, a.strides, a.__array_interface__["data"][0])
    return h, shape, strides


base = np.arange(24, dtype=np.int64).reshape(4, 6).copy()     # owns a 192-byte C-order buffer
D = base.ctypes.data
print(f"PyArrayObject field offsets: data={PyArrayObject.data.offset} nd={PyArrayObject.nd.offset} "
      f"dimensions={PyArrayObject.dimensions.offset} strides={PyArrayObject.strides.offset} "
      f"base={PyArrayObject.base.offset} descr={PyArrayObject.descr.offset} flags={PyArrayObject.flags.offset}")
print(f"{'expression':30} {'data-D':>6} {'shape':>11} {'strides':>11} {'base is':>8}  flags")
cases = [("a", base), ("a.T", base.T), ("a[::2, 1:]", base[::2, 1:]), ("a[:, 0]", base[:, 0]),
         ("a.reshape(6, 4)", base.reshape(6, 4)), ("broadcast_to(a[0], (1000,6))", np.broadcast_to(base[0], (1000, 6))),
         ("a.T.reshape(24)", base.T.reshape(24)), ("a.ravel()", base.ravel()), ("a.T.ravel()", base.T.ravel()),
         ("a[[0, 2]] (fancy)", base[[0, 2]]), ("a[a > 5] (mask)", base[base > 5]),
         ("np.ascontiguousarray(a.T)", np.ascontiguousarray(base.T))]
for label, v in cases:
    h, shape, strides = header(v)
    shares = np.shares_memory(v, base)
    where = "view" if shares else "COPY"
    owner = "a" if v.base is base else ("self" if v.base is None else type(v.base).__name__)
    flags = "|".join(n for n, bit in FLAGS if h.flags & bit)
    off = f"{h.data - D:6}" if shares else "   new"
    print(f"{label:30} {off} {str(shape):>11} {str(strides):>11} {owner:>8}  {flags}  [{where}]")

v = base[::2, 1:]
addr = v.ctypes.data + 1 * v.strides[0] + 3 * v.strides[1]       # v[1, 3]
assert addr == D + 2 * base.strides[0] + 4 * base.strides[1] and v[1, 3] == base[2, 4]
print(f"address(v[1,3]) = data + 1*{v.strides[0]} + 3*{v.strides[1]} = a's data + 2*48 + 4*8 -> same element "
      f"({v[1, 3]})")

print("== metadata-only (O(1)) vs data-moving (O(n)) operations on a 16M float64 array (128 MiB)")
big = np.random.default_rng(0).random((4096, 4096))


def t(fn, reps=5):
    best = float("inf")
    for _ in range(reps):
        t0 = time.perf_counter()
        fn()
        best = min(best, time.perf_counter() - t0)
    return best


for label, fn in [("big.T", lambda: big.T), ("big[::2, ::3]", lambda: big[::2, ::3]),
                  ("np.broadcast_to(big[0], (10**6, 4096))", lambda: np.broadcast_to(big[0], (10**6, 4096))),
                  ("big.reshape(-1)", lambda: big.reshape(-1)), ("big.copy()", big.copy),
                  ("big.T.reshape(-1)  (forces a copy)", lambda: big.T.reshape(-1)),
                  ("np.ascontiguousarray(big.T)", lambda: np.ascontiguousarray(big.T))]:
    dt = t(fn)
    unit = f"{dt * 1e9:9.0f} ns" if dt < 1e-4 else f"{dt * 1e3:9.1f} ms"
    print(f"  {label:42} {unit}")
huge = np.broadcast_to(big[0], (10**6, 4096))
print(f"  broadcast view claims {huge.nbytes / 2**30:.1f} GiB with strides {huge.strides}; writeable="
      f"{huge.flags.writeable}")
assert huge.strides[0] == 0 and not huge.flags.writeable
print("ALL ASSERTIONS PASSED")
```

Output (one measured run; the table is deterministic, timings vary):

```text
PyArrayObject field offsets: data=16 nd=24 dimensions=32 strides=40 base=48 descr=56 flags=64
expression                     data-D       shape     strides  base is  flags
a                                   0      (4, 6)     (48, 8)     self  C|OWNDATA|ALIGNED|WRITEABLE  [view]
a.T                                 0      (6, 4)     (8, 48)        a  F|ALIGNED|WRITEABLE  [view]
a[::2, 1:]                          8      (2, 5)     (96, 8)        a  ALIGNED|WRITEABLE  [view]
a[:, 0]                             0        (4,)       (48,)        a  ALIGNED|WRITEABLE  [view]
a.reshape(6, 4)                     0      (6, 4)     (32, 8)        a  C|ALIGNED|WRITEABLE  [view]
broadcast_to(a[0], (1000,6))        0   (1000, 6)      (0, 8)        a  ALIGNED  [view]
a.T.reshape(24)                   new       (24,)        (8,)  ndarray  C|F|ALIGNED|WRITEABLE  [COPY]
a.ravel()                           0       (24,)        (8,)        a  C|F|ALIGNED|WRITEABLE  [view]
a.T.ravel()                       new       (24,)        (8,)     self  C|F|OWNDATA|ALIGNED|WRITEABLE  [COPY]
a[[0, 2]] (fancy)                 new      (2, 6)     (48, 8)     self  C|OWNDATA|ALIGNED|WRITEABLE  [COPY]
a[a > 5] (mask)                   new       (18,)        (8,)     self  C|F|OWNDATA|ALIGNED|WRITEABLE  [COPY]
np.ascontiguousarray(a.T)         new      (6, 4)     (32, 8)     self  C|OWNDATA|ALIGNED|WRITEABLE  [COPY]
address(v[1,3]) = data + 1*96 + 3*8 = a's data + 2*48 + 4*8 -> same element (16)
== metadata-only (O(1)) vs data-moving (O(n)) operations on a 16M float64 array (128 MiB)
  big.T                                            300 ns
  big[::2, ::3]                                    300 ns
  np.broadcast_to(big[0], (10**6, 4096))          3600 ns
  big.reshape(-1)                                  300 ns
  big.copy()                                      30.1 ms
  big.T.reshape(-1)  (forces a copy)             228.4 ms
  np.ascontiguousarray(big.T)                    219.8 ms
  broadcast view claims 30.5 GiB with strides (0, 8); writeable=False
ALL ASSERTIONS PASSED
```

* Every *view* row shows `data - D` as a byte offset into the same buffer and `base is a`. Every *copy* row shows a new buffer. `a.T.reshape(24)` is the classic surprise: a reshape that must copy because the transposed order can't be strided.
* The O(1) operations cost **~0.2–4 µs whatever the size**. A contiguous copy of 128 MiB costs ~23–38 ms. A copy that *transposes* (`ascontiguousarray(big.T)`) costs ~200–230 ms, 6–9× more, because one side of it is a strided walk (§2.2).
* `broadcast_to` hands out a 30.5 GiB "array" with stride 0, read-only so you can't write through the aliasing.

### 2.2 Trap: walking memory against its layout

```python
"""stride_cache_physics.py - same element count, different strides: the cache line, not the FLOP, sets the speed.

A: compiled loops (Numba) over a C-order 4096x4096 float64 matrix in row-major vs column-major order.
B: reductions over views with identical element counts but different strides (every 64-byte line vs every word).
C: the cost of materializing a transpose, naive vs cache-blocked.
"""
import time

import numba
import numpy as np

N = 4096
A = np.random.default_rng(0).random((N, N))          # 128 MiB, C order: row i is contiguous


@numba.njit(cache=False)
def sum_row_major(a):
    s = 0.0
    for i in range(a.shape[0]):
        for j in range(a.shape[1]):
            s += a[i, j]                               # unit stride: 8 elements per 64-byte line
    return s


@numba.njit(cache=False)
def sum_col_major(a):
    s = 0.0
    for j in range(a.shape[1]):
        for i in range(a.shape[0]):
            s += a[i, j]                               # 32 KiB stride: a new line (and page) every access
    return s


@numba.njit(cache=False)
def transpose_naive(a, out):
    for i in range(a.shape[0]):
        for j in range(a.shape[1]):
            out[j, i] = a[i, j]


@numba.njit(cache=False)
def transpose_blocked(a, out, b):
    n = a.shape[0]
    for ii in range(0, n, b):
        for jj in range(0, n, b):
            for i in range(ii, ii + b):
                for j in range(jj, jj + b):
                    out[j, i] = a[i, j]


def best(fn, reps=3):
    t = []
    for _ in range(reps):
        t0 = time.perf_counter()
        r = fn()
        t.append(time.perf_counter() - t0)
    return min(t), r


sum_row_major(A[:8, :8])
sum_col_major(A[:8, :8])
out = np.empty_like(A)
transpose_naive(A[:64, :64], out[:64, :64])
transpose_blocked(A[:64, :64], out[:64, :64], 32)

print(f"== A. one compiled loop, two traversal orders ({A.nbytes / 2**20:.0f} MiB)")
t_r, s_r = best(lambda: sum_row_major(A))
t_c, s_c = best(lambda: sum_col_major(A))
assert abs(s_r - s_c) < 1e-6 * abs(s_r)
print(f"  row-major (stride 8 B)        {t_r * 1e3:7.1f} ms  {A.nbytes / t_r / 1e9:5.1f} GB/s")
print(f"  column-major (stride 32 KiB)  {t_c * 1e3:7.1f} ms  {A.nbytes / t_c / 1e9:5.1f} GB/s  ({t_c / t_r:.1f}x slower)")

print("== B. 2M elements each, summed by NumPy: what the stride does to bandwidth")


def lines_touched(v):
    """Exact number of distinct 64-byte lines covered by the view's elements."""
    rows = np.arange(v.shape[0])[:, None] * v.strides[0]
    cols = np.arange(v.shape[1])[None, :] * v.strides[1]
    return np.unique((v.ctypes.data - A.ctypes.data + rows + cols) // 64).size


views = [("A[:, :512]   (4096 runs of 512 contiguous)", A[:, :512]),
         ("A[:512]      (one contiguous 16 MiB block)", A[:512]),
         ("A.T[:512]    (same memory as A[:, :512])", A.T[:512]),
         ("A[:, ::8]    (1 element per cache line)", A[:, ::8])]
for label, v in views:
    assert v.size == N * 512
    dt, _ = best(lambda: v.sum())
    print(f"  {label:44} {dt * 1e3:6.2f} ms  ({v.size * 8 / dt / 1e9:5.1f} GB/s useful, "
          f"{lines_touched(v) * 64 / 2**20:4.0f} MiB of cache lines touched)")

print("== C. materializing a transpose")
t_copy, _ = best(lambda: A.copy())
t_np, _ = best(lambda: np.ascontiguousarray(A.T))
t_naive, _ = best(lambda: transpose_naive(A, out))
t_blk, _ = best(lambda: transpose_blocked(A, out, 32))
assert np.array_equal(out, A.T)
for label, dt in [("A.copy() (contiguous read + write)", t_copy), ("np.ascontiguousarray(A.T)", t_np),
                  ("naive i/j loop", t_naive), ("32x32 cache-blocked loop", t_blk)]:
    print(f"  {label:36} {dt * 1e3:7.1f} ms  ({dt / t_copy:4.1f}x a plain copy)")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. one compiled loop, two traversal orders (128 MiB)
  row-major (stride 8 B)           17.7 ms    7.6 GB/s
  column-major (stride 32 KiB)    180.3 ms    0.7 GB/s  (10.2x slower)
== B. 2M elements each, summed by NumPy: what the stride does to bandwidth
  A[:, :512]   (4096 runs of 512 contiguous)     1.56 ms  ( 10.8 GB/s useful,   16 MiB of cache lines touched)
  A[:512]      (one contiguous 16 MiB block)     2.24 ms  (  7.5 GB/s useful,   16 MiB of cache lines touched)
  A.T[:512]    (same memory as A[:, :512])       1.72 ms  (  9.7 GB/s useful,   16 MiB of cache lines touched)
  A[:, ::8]    (1 element per cache line)        6.64 ms  (  2.5 GB/s useful,  128 MiB of cache lines touched)
== C. materializing a transpose
  A.copy() (contiguous read + write)      23.2 ms  ( 1.0x a plain copy)
  np.ascontiguousarray(A.T)              213.5 ms  ( 9.2x a plain copy)
  naive i/j loop                         223.1 ms  ( 9.6x a plain copy)
  32x32 cache-blocked loop                75.7 ms  ( 3.3x a plain copy)
ALL ASSERTIONS PASSED
```

* **A:** the same compiled loop is **~10× slower column-first** (0.7 against 7–8 GB/s). The row-major loop is itself limited by the latency of the dependent floating-point add chain (no `fastmath`, so no vectorized reduction). NumPy's pairwise `sum` reaches 11 GB/s on the same data.
* **B:** four views with the same 2 M elements. The three that touch 16 MiB of lines run at 7.5–11 GB/s, regardless of whether *you* wrote `.T`, because NumPy reorders iteration. `A[:, ::8]` touches 128 MiB of lines for 16 MiB of data and runs ~4× slower.
* **C:** materializing a transpose is 9× a plain copy, naive or via NumPy. A **32×32 cache-blocked** loop brings it to ~3× by keeping both the read tile and the write tile in L1. **Pattern:** choose the layout for the dominant access (C order for row-wise feature vectors, F order or a transposed copy made *once* for column scans). Hand-written loops go in memory order, and big transposes are tiled.

### 2.3 Trap: hidden allocations in "vectorized" code

```python
"""broadcast_copy_traps.py - where NumPy silently allocates: temporaries, promotion, broadcasting, fancy indexing.

NumPy reports its data buffers to tracemalloc (domain np.lib.tracemalloc_domain), so peak bytes are measurable.
"""
import time
import tracemalloc

import numpy as np

MB = 2**20
rng = np.random.default_rng(0)


def peak(fn):
    tracemalloc.start()
    t0 = time.perf_counter()
    r = fn()
    dt = time.perf_counter() - t0
    _, pk = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    return r, pk, dt


print("== A. expression temporaries: y = a * 2.0 + 1.0 on 32M float64 (256 MiB per array)")
a = rng.random(32 * MB)
y = np.empty_like(a)


def naive():
    return a * 2.0 + 1.0                       # tmp = a*2 (256 MiB), result = tmp + 1 (256 MiB)


def in_place():
    np.multiply(a, 2.0, out=y)                 # reuse a preallocated output: zero new buffers
    np.add(y, 1.0, out=y)
    return y


r1, p1, t1 = peak(naive)
r2, p2, t2 = peak(in_place)
assert np.array_equal(r1, r2)
del r1
print(f"  a * 2.0 + 1.0              peak new memory {p1 / MB:7.1f} MiB   {t1 * 1e3:6.1f} ms")
print(f"  multiply(out=) + add(out=) peak new memory {p2 / MB:7.1f} MiB   {t2 * 1e3:6.1f} ms")

print("== B. NumPy 2 promotion (NEP 50): Python scalars are 'weak', NumPy scalars/arrays are not")
f32 = np.ones(4, dtype=np.float32)
cases = [("float32 array * 2.5 (python float)", f32 * 2.5),
         ("float32 array * np.float64(2.5)", f32 * np.float64(2.5)),
         ("float32 array * float64 array", f32 * np.ones(4)),
         ("int32 array + 1.5", np.ones(4, np.int32) + 1.5),
         ("uint8 array + 1", np.full(4, 255, np.uint8) + 1)]
for label, r in cases:
    print(f"  {label:38} -> {str(r.dtype):8} {r.itemsize} B/elem   first={r[0]!r}")
try:
    np.full(4, 1, np.uint8) + 300
except OverflowError as e:
    print(f"  uint8 array + 300                      -> OverflowError: {e}")

print("== C. broadcasting multiplies shapes: pairwise distances for N points in 16-D")
for n in (5_000, 50_000):
    print(f"  N={n:>6}: (N,1,16) - (1,N,16) materializes {n * n * 16 * 8 / 2**30:8.2f} GiB; "
          f"the N x N result alone is {n * n * 8 / 2**30:6.2f} GiB")
n = 3_000
pts = rng.random((n, 16))


def broadcast_dist():
    d = pts[:, None, :] - pts[None, :, :]       # (n, n, 16) temporary
    return np.sqrt((d * d).sum(-1))


def gram_dist():
    sq = (pts * pts).sum(1)                     # ||x||^2 + ||y||^2 - 2 x.y : one BLAS matmul, n x n output
    g = sq[:, None] + sq[None, :] - 2.0 * (pts @ pts.T)
    np.maximum(g, 0.0, out=g)
    return np.sqrt(g, out=g)


d1, pk1, t1 = peak(broadcast_dist)
d2, pk2, t2 = peak(gram_dist)
assert np.allclose(d1, d2, atol=1e-6)
print(f"  N={n}: broadcast (n,n,16)      peak {pk1 / MB:7.1f} MiB  {t1 * 1e3:7.1f} ms")
print(f"  N={n}: Gram/BLAS formulation   peak {pk2 / MB:7.1f} MiB  {t2 * 1e3:7.1f} ms  ({t1 / t2:.1f}x faster)")

print("== D. fancy indexing always copies; give it an output buffer")
src = rng.random(8 * MB)
idx = rng.integers(0, src.size, 4 * MB)
buf = np.empty(idx.size)
_, pk_a, t_a = peak(lambda: src[idx])
_, pk_b, t_b = peak(lambda: np.take(src, idx, out=buf))              # mode='raise': out is buffered!
_, pk_c, t_c = peak(lambda: np.take(src, idx, out=buf, mode="clip"))
assert np.array_equal(buf, src[idx])
print(f"  src[idx]                              new {pk_a / MB:6.1f} MiB  {t_a * 1e3:6.1f} ms")
print(f"  np.take(..., out=buf)                 new {pk_b / MB:6.1f} MiB  {t_b * 1e3:6.1f} ms  (default mode='raise')")
print(f"  np.take(..., out=buf, mode='clip')    new {pk_c / MB:6.1f} MiB  {t_c * 1e3:6.1f} ms")

print("== E. windows without copies: sliding_window_view (read-only stride trick) vs materialized windows")
x = rng.random(1_000_000)
w = 64
win, pk_v, t_v = peak(lambda: np.lib.stride_tricks.sliding_window_view(x, w))
print(f"  sliding_window_view: shape {win.shape}, strides {win.strides}, writeable={win.flags.writeable}, "
      f"new {pk_v / MB:.2f} MiB")
c = np.concatenate(([0.0], np.cumsum(x)))
_, pk_c, t_c = peak(lambda: (c[w:] - c[:-w]) / w)
_, pk_m, t_m = peak(lambda: win.mean(axis=1))
assert np.allclose((c[w:] - c[:-w]) / w, win.mean(axis=1))
print(f"  rolling mean via window view .mean(1): {t_m * 1e3:6.1f} ms (O(n*w) reads)")
print(f"  rolling mean via prefix sums         : {t_c * 1e3:6.1f} ms (O(n), {pk_c / MB:.1f} MiB)")
print("ALL ASSERTIONS PASSED")
```

Output (one measured run):

```text
== A. expression temporaries: y = a * 2.0 + 1.0 on 32M float64 (256 MiB per array)
  a * 2.0 + 1.0              peak new memory   512.0 MiB    137.0 ms
  multiply(out=) + add(out=) peak new memory     0.0 MiB     87.5 ms
== B. NumPy 2 promotion (NEP 50): Python scalars are 'weak', NumPy scalars/arrays are not
  float32 array * 2.5 (python float)     -> float32  4 B/elem   first=np.float32(2.5)
  float32 array * np.float64(2.5)        -> float64  8 B/elem   first=np.float64(2.5)
  float32 array * float64 array          -> float64  8 B/elem   first=np.float64(1.0)
  int32 array + 1.5                      -> float64  8 B/elem   first=np.float64(2.5)
  uint8 array + 1                        -> uint8    1 B/elem   first=np.uint8(0)
  uint8 array + 300                      -> OverflowError: Python integer 300 out of bounds for uint8
== C. broadcasting multiplies shapes: pairwise distances for N points in 16-D
  N=  5000: (N,1,16) - (1,N,16) materializes     2.98 GiB; the N x N result alone is   0.19 GiB
  N= 50000: (N,1,16) - (1,N,16) materializes   298.02 GiB; the N x N result alone is  18.63 GiB
  N=3000: broadcast (n,n,16)      peak  2265.9 MiB    971.4 ms
  N=3000: Gram/BLAS formulation   peak   206.0 MiB    183.3 ms  (5.3x faster)
== D. fancy indexing always copies; give it an output buffer
  src[idx]                              new   32.0 MiB    61.7 ms
  np.take(..., out=buf)                 new   32.0 MiB   114.2 ms  (default mode='raise')
  np.take(..., out=buf, mode='clip')    new    0.0 MiB    94.3 ms
== E. windows without copies: sliding_window_view (read-only stride trick) vs materialized windows
  sliding_window_view: shape (999937, 64), strides (8, 8), writeable=False, new 0.00 MiB
  rolling mean via window view .mean(1):   26.5 ms (O(n*w) reads)
  rolling mean via prefix sums         :    5.8 ms (O(n), 15.3 MiB)
ALL ASSERTIONS PASSED
```

* **A:** `a * 2.0 + 1.0` allocates **512 MiB of temporaries for a 256 MiB input**: one buffer per operator, each also paying first-touch page faults. With `out=` the peak is zero and it runs ~1.5× faster. NumPy can elide temporaries when an operand's refcount proves it's a temporary, but only on builds and platforms that support the check. This Windows run shows none (512 MiB = two full buffers), so don't rely on it.
* **B:** NEP 50 in practice. Python scalars keep your dtype; NumPy float64 scalars and arrays up-cast it. `int32 + 1.5` doubles memory.
* **C:** the broadcast formulation of pairwise distance peaks at **2.2 GiB for N = 3 000** and is ~5–12× slower than the Gram/BLAS formulation (‖x‖² + ‖y‖² − 2·XYᵀ), which allocates only the N×N result and runs on a tuned matmul. **Pattern:** never materialize a 3-D broadcast to reduce it; rewrite it as matmul, or chunk the outer axis.
* **D:** fancy indexing always gathers into a new array. `np.take(..., out=buf)` still buffers internally in the default `mode='raise'` (it must validate every index before writing); `mode='clip'` writes straight into `buf` with zero new memory.
* **E:** `sliding_window_view` gives a zero-copy (n−w+1, w) window matrix with stride (8, 8), read-only for safety. It still does O(n·w) work; prefix sums do O(n) and are 4–6× faster for rolling means. Never use raw `as_strided` with hand-computed strides: a wrong stride reads outside the buffer with no error.

---

## 3. Production Failure Modes & Debugging

| # | Symptom | Signature | Root cause | Fix | Prevention |
|---|---|---|---|---|---|
| F1 🔥 | `MemoryError` / OOM-kill on a "simple" NumPy line | Peak RSS ≫ input size; tracemalloc shows several same-size buffers | Expression temporaries, or a broadcast materializing an N×N×D cube | `out=` chains, `numexpr`/Numba fusion (02.2), Gram/BLAS rewrites, chunking | Review any broadcast that produces > 2 dimensions; tracemalloc peak in tests |
| F2 ⚡ | Transform 5–10× slower after a refactor | Same FLOPs; profile dominated by a copy or a strided loop | Data became F-order or transposed (e.g. `df.values.T`, `np.loadtxt` of column data) | `np.ascontiguousarray` once at the boundary; loops in memory order | Assert `x.flags.c_contiguous` at hot-function entry |
| F3 🔥 | Writes "disappear" or show up elsewhere | Mutating a slice changes the parent, or mutating a fancy-indexed result doesn't | Views alias (slices); copies don't (fancy/boolean indexing) | Know the rule: basic indexing = view, advanced indexing = copy; `.copy()` explicitly | `np.shares_memory` assertions in tests; `arr.flags.writeable = False` for shared inputs |
| F4 | Huge array never freed | A tiny slice is kept in a cache; RSS stays at the parent's size | A view's `base` keeps the whole parent buffer alive | `small = big[idx].copy()` before caching | Lint: no views of large arrays stored in long-lived structures |
| F5 | Memory doubled after "harmless" arithmetic | dtype changed from float32 to float64 | NEP 50 promotion with a NumPy float64 scalar or array | Keep scalars as Python floats or cast explicitly | dtype assertions at module boundaries |
| F6 🔥 | Garbage values or segfaults from a windowing utility | Values beyond the array end | `as_strided` with wrong strides or shape | `sliding_window_view` (bounds-checked, read-only) | Ban `as_strided` in code review |
| F7 | Wrong results after a uint8/int16 pipeline step | Values wrap silently | In-range integer arithmetic wraps (no overflow check) | Widen before arithmetic (`astype(np.int32)`), or `np.clip` | Property tests at dtype edges |
| F8 | `np.take(out=buf)` doesn't save memory | Peak equals output size | `mode='raise'` buffers to validate indices | `mode='clip'` or `'wrap'` after validating indices once | Read the `out=` notes of each API |

**Debugging toolkit.** `a.flags`, `a.strides`, `a.base` and `np.shares_memory(a, b)` answer "view or copy?". `a.__array_interface__['data'][0]` gives the buffer address, for comparing whether two arrays share memory. `tracemalloc` sees NumPy buffers (domain `np.lib.tracemalloc_domain`), so `get_traced_memory()` peaks are exact. `np.show_config()` / `np.show_runtime()` show the BLAS and SIMD build.

---

## 4. L7 Bar-Raiser Q&A Chains

<details><summary><b>Q1 · "Why is `arr.T` free but `arr.T.copy()` takes 200 ms?"</b></summary>

**Initial Prompt.** Explain the cost difference between transposing and materializing a transpose of a 4096×4096 float64 matrix.

**L5 Answer.** "Transpose is lazy; the copy has to move 128 MB."

**Why L5 Crashes at Scale.** "Moving 128 MB" predicts ~25–40 ms (a plain copy measured 23–38 ms). The transposed copy is 6–9× slower, and the L5 model can't explain that. Engineers who budget by bytes alone under-provision pipelines that transpose (image channels-first↔last, columnar↔row batches) by an order of magnitude.

**L7 Principal Defense.** `.T` swaps two `npy_intp` values in a new header (~0.3 µs). The copy reads one side with a 32 KiB stride, so every element costs a full cache line and a TLB lookup: 64 B fetched for 8 B used, no prefetch help. Measured: naive loop 9.6× a plain copy, a 32×32 tiled loop 3.3×. The fixes are to choose the layout at the producer so consumers don't transpose, to tile any unavoidable transpose (or let the BLAS/library do it), and to transpose *once* at a boundary, never inside an inner loop.

</details>

<details><summary><b>Q2 · "A 16 GB box OOMs computing pairwise distances for 50k points. Fix it."</b></summary>

**Initial Prompt.** `d = np.sqrt(((X[:, None, :] - X[None, :, :])**2).sum(-1))` with X of shape (50 000, 16).

**L5 Answer.** "Use float32 to halve memory."

**Why L5 Crashes at Scale.** The broadcast intermediate is 50 000² × 16 × 8 B = **298 GiB** (computed in §2.3). float32 makes it 149 GiB. Even the final N×N float64 result is 18.6 GiB. Halving the dtype doesn't change the asymptotics.

**L7 Principal Defense.** Remove the D axis with algebra: ‖x−y‖² = ‖x‖² + ‖y‖² − 2x·y, so the cube becomes one matmul (BLAS, cache-blocked, multithreaded). Measured at N = 3 000: 2.2 GiB → 206 MiB peak and 5–12× faster. Then question the N×N output itself. Stream it in row blocks (`for i in range(0, N, B)`) and reduce on the fly (top-k neighbours, thresholded pairs), or use an index (FAISS, a KD-tree) so the quadratic matrix never exists. Clamp tiny negative values from cancellation before `sqrt`, as the listing does.

</details>

<details><summary><b>Q3 · "When does `reshape` copy?"</b></summary>

**Initial Prompt.** A team assumes `reshape` is always free and builds a pipeline of `transpose → reshape → model`.

**L5 Answer.** "Reshape never copies; it just changes the shape."

**Why L5 Crashes at Scale.** `reshape` returns a view only if the new shape can be addressed with strides over the existing layout. After a transpose it usually can't, and NumPy silently copies (measured: `big.T.reshape(-1)` 228 ms against 0.3 µs for `big.reshape(-1)`). In a per-batch pipeline that's a full copy per batch, hidden in a line that looks free.

**L7 Principal Defense.** Model the rule: merging axes `i` and `i+1` into one needs `strides[i] == shape[i+1] * strides[i+1]`. Check with `np.shares_memory(out, x)` or `out.base is x` in tests, and fail loudly when a copy is unwanted: `np.reshape(x, shape, copy=False)` raises instead of copying. (Assigning to `x.shape` did the same but is deprecated in NumPy 2.5, verified.) Push the transpose to where the data is produced, or let the consumer accept strides (most BLAS calls, PyTorch ops and Arrow-to-tensor paths can).

</details>

<details><summary><b>Q4 · "Our feature service's memory doubled after a NumPy 2 upgrade. Why?"</b></summary>

**Initial Prompt.** Arrays that used to stay float32 are now float64 in some code paths, or the other way round, and results changed slightly.

**L5 Answer.** "NumPy 2 changed defaults; cast everything to float32."

**Why L5 Crashes at Scale.** Blanket casting hides *where* promotion happens and can lose precision where float64 was intended (accumulators). The actual cause is NEP 50: value-based casting is gone. Python scalars are weak, NumPy scalars are strong, and out-of-range Python ints now raise.

**L7 Principal Defense.** Audit the scalar types at the boundary. A `np.float64` coming from a reduction (`x.mean()`) multiplied into a float32 array now up-casts (measured: `float32 * np.float64(2.5) → float64`), where `float32 * 2.5` stays float32. Fix by converting such scalars with `float()` or casting arrays deliberately. Keep accumulators in float64 (`sum(dtype=np.float64)`, 02.2) and storage in float32. Add dtype assertions to the feature contract, and run the test suite with `np.errstate(over='raise')` where integer overflow is a correctness issue.

</details>

<details><summary><b>Q5 · "Explain broadcasting to a C++ engineer in one minute, and its cost model."</b></summary>

**Initial Prompt.** What does `a[:, None] + b[None, :]` compile to, conceptually?

**L5 Answer.** "NumPy copies the smaller array to match the bigger one's shape."

**Why L5 Crashes at Scale.** No copy of the inputs happens, but the *output* is the full broadcast shape. People who believe "inputs are copied" optimize the wrong side and miss that the output dominates (N×M), or that a later reduction could have avoided materializing it.

**L7 Principal Defense.** Broadcasting builds an iterator over the output shape where each operand has stride 0 on its stretched axes. It's an `std::mdspan` with `layout_stride` and zero strides feeding a nested loop. Inputs cost nothing extra; the output costs N×M×itemsize and one write pass. So the rules are: broadcast freely when the output is what you need; when you only need a reduction of it, fuse (Numba/numexpr) or use algebra (matmul, `np.einsum` with `optimize=True`) so the broadcast shape is never stored.

</details>

<details><summary><b>Q6 · "Why does looping over a NumPy array in Python run slower than looping over a list?"</b></summary>

**Initial Prompt.** A developer converts lists to arrays "for speed", but the Python loop gets 2–3× slower.

**L5 Answer.** "NumPy has overhead for small operations."

**Why L5 Crashes at Scale.** The cost is per *element*, not per call: `arr[i]` creates a new `np.float64` scalar object each time (allocation + boxing + dtype dispatch), where a list hands out an existing `float`. Measured in 02.2: the same recurrence takes 2.0 s indexing ndarrays against 0.79 s over `.tolist()`. Converting to arrays without vectorizing makes code *slower*.

**L7 Principal Defense.** NumPy's speed exists only inside its C loops. Either express the computation as whole-array operations, compile the loop (Numba/Cython/C: 30–45× in 02.2), or keep plain lists for scalar-at-a-time logic. The decision rule is that an ndarray is the right container when the consumer is a C loop (ufunc, BLAS, Arrow, a compiled kernel) and the wrong one when the consumer is a Python `for`.

</details>

<details><summary><b>Q7 · "A cache holds small slices of large arrays and memory grows without bound. Explain."</b></summary>

**Initial Prompt.** A service caches `embedding[i:i+1]` for hot items; RSS grows far beyond the number of cached rows.

**L5 Answer.** "Python's memory isn't returned to the OS."

**Why L5 Crashes at Scale.** Each slice is a view whose `base` references the whole parent buffer, so caching one 1 KB row pins a multi-GB embedding table batch. Every refreshed parent that's kept alive by an old slice is another full copy in memory.

**L7 Principal Defense.** Check `v.base is not None` and `v.base.nbytes` for cached objects. The fix is `row = embedding[i].copy()` (or `np.array(view, copy=True)`) before storing, so the cache owns exactly what it holds. Better still, cache *indices* into one long-lived table. The same aliasing rule applies to Arrow slices (02.3) and PyTorch views (06.1), where a small view can pin a whole GPU allocation.

</details>

<details><summary><b>Q8 · "How would you speed up a rolling-window feature over 1 billion rows?"</b></summary>

**Initial Prompt.** Rolling 64-sample means per device over 1 B readings; the current pandas `.rolling()` job takes hours.

**L5 Answer.** "Use `sliding_window_view` and `.mean(axis=1)`, which is vectorized."

**Why L5 Crashes at Scale.** It's zero-copy but still O(n·w) reads: 64 B billion element reads, ~5× slower than necessary (measured: 26.5 vs 5.8 ms per million). And at 1 B rows the view's `.mean` materializes nothing, but anything that touches `win.copy()` or fancy-indexes it materializes n×w.

**L7 Principal Defense.** Use O(n) algebra: prefix sums (`c[w:] - c[:-w]`) for means, two prefix sums for variance (in float64, or Welford in a compiled loop for numerical stability), and monotonic deques in Numba for rolling max/min. Partition by device so each partition fits in cache-friendly chunks, and run partitions in parallel (Numba `prange`, Polars `rolling_*_by` over sorted data, DuckDB window functions, 03.4). Persist only the features, never the windows.

</details>

---

## 5. Invariants Checklist

- [ ] An ndarray = `data` pointer + `shape` + byte `strides` + dtype + flags. Element address = `data + Σ iₖ·strideₖ`.
- [ ] Basic slicing, transpose, broadcast and compatible reshape are O(1) views. Fancy/boolean indexing, incompatible reshape and `flatten` copy.
- [ ] Views keep their parent's whole buffer alive via `base`. Copy before caching small pieces.
- [ ] The cache line (64 B) is the unit of cost. Stride ≥ 64 B wastes ≥ 7/8 of bandwidth, and page-sized strides also thrash the TLB.
- [ ] NumPy's own loops reorder axes to memory order; your hand-written loops don't.
- [ ] Broadcasting costs nothing on inputs and everything on the output shape. Never materialize a broadcast just to reduce it.
- [ ] Every operator in an expression allocates. Use `out=` chains or fusion for large arrays.
- [ ] NEP 50: Python scalars are weak and NumPy scalars are strong. In-range integer arithmetic wraps silently.
- [ ] There's no `is_contiguous()` in NumPy: use `flags.c_contiguous`, `np.shares_memory`, `base`.

---

## 6. References

- NumPy C-API, array structure and flags (`PyArrayObject`, `NPY_ARRAY_*`) — https://numpy.org/doc/stable/reference/c-api/types-and-structures.html
- NumPy internals: strides and the memory layout — https://numpy.org/doc/stable/dev/internals.html
- NumPy indexing (views vs copies) — https://numpy.org/doc/stable/user/basics.indexing.html
- Copies and views — https://numpy.org/doc/stable/user/basics.copies.html
- Broadcasting — https://numpy.org/doc/stable/user/basics.broadcasting.html
- NEP 50, Promotion rules for Python scalars — https://numpy.org/neps/nep-0050-scalar-promotion.html
- NEP 49, Data allocation strategies (`mem_handler`) — https://numpy.org/neps/nep-0049-data-allocation-strategies.html
- `numpy.take` (`out` buffering with `mode='raise'`) — https://numpy.org/doc/stable/reference/generated/numpy.take.html
- `sliding_window_view` — https://numpy.org/doc/stable/reference/generated/numpy.lib.stride_tricks.sliding_window_view.html
- U. Drepper, "What Every Programmer Should Know About Memory" (2007) — https://people.freebsd.org/~lstewart/articles/cpumemory.pdf
- `std::mdspan` (C++23, layout_stride) — https://en.cppreference.com/w/cpp/container/mdspan
